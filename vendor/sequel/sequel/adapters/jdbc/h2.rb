module Sequel
  module JDBC
    # Database and Dataset support for H2 databases accessed via JDBC.
    module H2
      # Instance methods for H2 Database objects accessed via JDBC.
      module DatabaseMethods
        PRIMARY_KEY_INDEX_RE = /\Aprimary_key/i.freeze
      
        # Commit an existing prepared transaction with the given transaction
        # identifier string.
        def commit_prepared_transaction(transaction_id)
          run("COMMIT TRANSACTION #{transaction_id}")
        end

        # H2 uses the :h2 database type.
        def database_type
          :h2
        end

        # Rollback an existing prepared transaction with the given transaction
        # identifier string.
        def rollback_prepared_transaction(transaction_id)
          run("ROLLBACK TRANSACTION #{transaction_id}")
        end

        # H2 uses an IDENTITY type
        def serial_primary_key_options
          {:primary_key => true, :type => :identity}
        end

        # H2 supports CREATE TABLE IF NOT EXISTS syntax.
        def supports_create_table_if_not_exists?
          true
        end
      
        # H2 supports prepared transactions
        def supports_prepared_transactions?
          true
        end
        
        # H2 supports savepoints
        def supports_savepoints?
          true
        end
        
        private
        
        # If the :prepare option is given and we aren't in a savepoint,
        # prepare the transaction for a two-phase commit.
        def commit_transaction(conn, opts={})
          if (s = opts[:prepare]) && @transactions[conn][:savepoint_level] <= 1
            log_connection_execute(conn, "PREPARE COMMIT #{s}")
          else
            super
          end
        end

        # H2 needs to add a primary key column as a constraint
        def alter_table_sql(table, op)
          case op[:op]
          when :add_column
            if (pk = op.delete(:primary_key)) || (ref = op.delete(:table))
              sqls = [super(table, op)]
              sqls << "ALTER TABLE #{quote_schema_table(table)} ADD PRIMARY KEY (#{quote_identifier(op[:name])})" if pk
              if ref
                op[:table] = ref
                sqls << "ALTER TABLE #{quote_schema_table(table)} ADD FOREIGN KEY (#{quote_identifier(op[:name])}) #{column_references_sql(op)}"
              end
              sqls
            else
              super(table, op)
            end
          when :rename_column
            "ALTER TABLE #{quote_schema_table(table)} ALTER COLUMN #{quote_identifier(op[:name])} RENAME TO #{quote_identifier(op[:new_name])}"
          when :set_column_null
            "ALTER TABLE #{quote_schema_table(table)} ALTER COLUMN #{quote_identifier(op[:name])} SET#{' NOT' unless op[:null]} NULL"
          when :set_column_type
            "ALTER TABLE #{quote_schema_table(table)} ALTER COLUMN #{quote_identifier(op[:name])} #{type_literal(op)}"
          else
            super(table, op)
          end
        end
        
        # Default to a single connection for a memory database.
        def connection_pool_default_options
          o = super
          uri == 'jdbc:h2:mem:' ? o.merge(:max_connections=>1) : o
        end
      
        # Use IDENTITY() to get the last inserted id.
        def last_insert_id(conn, opts={})
          statement(conn) do |stmt|
            sql = 'SELECT IDENTITY();'
            rs = log_yield(sql){stmt.executeQuery(sql)}
            rs.next
            rs.getInt(1)
          end
        end
        
        def primary_key_index_re
          PRIMARY_KEY_INDEX_RE
        end
      end
      
      # Dataset class for H2 datasets accessed via JDBC.
      class Dataset < JDBC::Dataset
        SELECT_CLAUSE_METHODS = clause_methods(:select, %w'distinct columns from join where group having compounds order limit')
        BITWISE_METHOD_MAP = {:& =>:BITAND, :| => :BITOR, :^ => :BITXOR}
        
        # Emulate the case insensitive LIKE operator and the bitwise operators.
        def complex_expression_sql(op, args)
          case op
          when :ILIKE
            super(:LIKE, [SQL::PlaceholderLiteralString.new("CAST(? AS VARCHAR_IGNORECASE)", [args.at(0)]), args.at(1)])
          when :"NOT ILIKE"
            super(:"NOT LIKE", [SQL::PlaceholderLiteralString.new("CAST(? AS VARCHAR_IGNORECASE)", [args.at(0)]), args.at(1)])
          when :&, :|, :^
            complex_expression_arg_pairs(args){|a, b| literal(SQL::Function.new(BITWISE_METHOD_MAP[op], a, b))}
          when :<<
            complex_expression_arg_pairs(args){|a, b| "(#{literal(a)} * POWER(2, #{literal(b)}))"}
          when :>>
            complex_expression_arg_pairs(args){|a, b| "(#{literal(a)} / POWER(2, #{literal(b)}))"}
          when :'B~'
            "((0 - #{literal(args.at(0))}) - 1)"
          else
            super(op, args)
          end
        end
        
        # H2 requires SQL standard datetimes
        def requires_sql_standard_datetimes?
          true
        end

        # H2 doesn't support IS TRUE
        def supports_is_true?
          false
        end
        
        # H2 doesn't support JOIN USING
        def supports_join_using?
          false
        end
        
        # H2 doesn't support multiple columns in IN/NOT IN
        def supports_multiple_column_in?
          false
        end 

        private
      
        # Handle H2 specific clobs as strings.
        def convert_type(v)
          case v
          when Java::OrgH2Jdbc::JdbcClob
            convert_type(v.getSubString(1, v.length))
          else
            super(v)
          end
        end
        
        # H2 expects hexadecimal strings for blob values
        def literal_blob(v)
          literal_string v.unpack("H*").first
        end
        
        # H2 handles fractional seconds in timestamps, but not in times
        def literal_sqltime(v)
          v.strftime("'%H:%M:%S'")
        end

        def select_clause_methods
          SELECT_CLAUSE_METHODS
        end
      end
    end
  end
end
