Sequel.require 'adapters/jdbc/transactions'

module Sequel
  module JDBC
    # Database and Dataset support for HSQLDB databases accessed via JDBC.
    module HSQLDB
      # Instance methods for HSQLDB Database objects accessed via JDBC.
      module DatabaseMethods
        include ::Sequel::JDBC::Transactions

        # HSQLDB uses the :hsqldb database type.
        def database_type
          :hsqldb
        end

        # HSQLDB uses an IDENTITY sequence as the default value for primary
        # key columns.
        def serial_primary_key_options
          {:primary_key => true, :type => :integer, :identity=>true, :start_with=>1}
        end

        # The version of the database, as an integer (e.g 2.2.5 -> 20205)
        def db_version
          @db_version ||= begin
            v = get{DATABASE_VERSION(){}}
            if v =~ /(\d+)\.(\d+)\.(\d+)/
              $1.to_i * 10000 + $2.to_i * 100 + $3.to_i
            end
          end
        end
        
        private
        
        # HSQLDB specific SQL for renaming columns, and changing column types and/or nullity.
        def alter_table_sql(table, op)
          case op[:op]
          when :rename_column
            "ALTER TABLE #{quote_schema_table(table)} ALTER COLUMN #{quote_identifier(op[:name])} RENAME TO #{quote_identifier(op[:new_name])}"
          when :set_column_type
            "ALTER TABLE #{quote_schema_table(table)} ALTER COLUMN #{quote_identifier(op[:name])} SET DATA TYPE #{type_literal(op)}"
          when :set_column_null
            "ALTER TABLE #{quote_schema_table(table)} ALTER COLUMN #{quote_identifier(op[:name])} SET #{op[:null] ? 'NULL' : 'NOT NULL'}"
          else
            super
          end
        end

        # Use IDENTITY() to get the last inserted id.
        def last_insert_id(conn, opts={})
          statement(conn) do |stmt|
            sql = 'CALL IDENTITY()'
            rs = log_yield(sql){stmt.executeQuery(sql)}
            rs.next
            rs.getInt(1)
          end
        end

        # If an :identity option is present in the column, add the necessary IDENTITY SQL.
        # It's possible to use an IDENTITY type, but that defaults the sequence to start
        # at 0 instead of 1, and we don't want that.
        def type_literal(column)
          if column[:identity]
            sql = "#{super} GENERATED BY DEFAULT AS IDENTITY"
            if sw = column[:start_with]
              sql << " (START WITH #{sw.to_i}"
              sql << " INCREMENT BY #{column[:increment_by].to_i}" if column[:increment_by]
              sql << ")"
            end
            sql
          else
            super
          end
        end
      end
      
      # Dataset class for HSQLDB datasets accessed via JDBC.
      class Dataset < JDBC::Dataset
        BITWISE_METHOD_MAP = {:& =>:BITAND, :| => :BITOR, :^ => :BITXOR}
        BOOL_TRUE = 'TRUE'.freeze
        BOOL_FALSE = 'FALSE'.freeze
        # HSQLDB does support common table expressions, but the support is broken.
        # CTEs operate more like temprorary tables or views, lasting longer than the duration of the expression.
        # CTEs in earlier queries might take precedence over CTEs with the same name in later queries.
        # Also, if any CTE is recursive, all CTEs must be recursive.
        # If you want to use CTEs with HSQLDB, you'll have to manually modify the dataset to allow it.
        SELECT_CLAUSE_METHODS = clause_methods(:select, %w'distinct columns from join where group having compounds order limit lock')
        SQL_WITH_RECURSIVE = "WITH RECURSIVE ".freeze

        # Handle HSQLDB specific case insensitive LIKE and bitwise operator support.
        def complex_expression_sql(op, args)
          case op
          when :ILIKE
            super(:LIKE, [SQL::Function.new(:ucase, args.at(0)), SQL::Function.new(:ucase, args.at(1)) ])
          when :"NOT ILIKE"
            super(:"NOT LIKE", [SQL::Function.new(:ucase, args.at(0)), SQL::Function.new(:ucase, args.at(1)) ])
          when :&, :|, :^
            op = BITWISE_METHOD_MAP[op]
            complex_expression_arg_pairs(args){|a, b| literal(SQL::Function.new(op, a, b))}
          when :<<
            complex_expression_arg_pairs(args){|a, b| "(#{literal(a)} * POWER(2, #{literal(b)}))"}
          when :>>
            complex_expression_arg_pairs(args){|a, b| "(#{literal(a)} / POWER(2, #{literal(b)}))"}
          when :'B~'
            "((0 - #{literal(args.at(0))}) - 1)"
          else
            super
          end
        end

        # HSQLDB requires recursive CTEs to have column aliases.
        def recursive_cte_requires_column_aliases?
          true
        end

        # HSQLDB does not support IS TRUE.
        def supports_is_true?
          false
        end

        private

        # Use string in hex format for blob data.
        def literal_blob(v)
          blob = "X'"
          v.each_byte{|x| blob << sprintf('%02x', x)}
          blob << "'"
          blob
        end

        # HSQLDB uses FALSE for false values.
        def literal_false
          BOOL_FALSE
        end

        # HSQLDB handles fractional seconds in timestamps, but not in times
        def literal_sqltime(v)
          v.strftime("'%H:%M:%S'")
        end

        # HSQLDB uses TRUE for true values.
        def literal_true
          BOOL_TRUE
        end

        # HSQLDB does not support CTEs well enough for Sequel to enable support for them.
        def select_clause_methods
          SELECT_CLAUSE_METHODS
        end

        # Use a default FROM table if the dataset does not contain a FROM table.
        def select_from_sql(sql)
          if @opts[:from]
            super
          else
            sql << " FROM (VALUES (0))"
          end
        end
        
        # Use WITH RECURSIVE instead of WITH if any of the CTEs is recursive
        def select_with_sql_base
          opts[:with].any?{|w| w[:recursive]} ? SQL_WITH_RECURSIVE : super
        end
      end
    end
  end
end
