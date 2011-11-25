module Sequel
  module Informix
    module DatabaseMethods
      TEMPORARY = 'TEMP '.freeze

      # Informix uses the :informix database type
      def database_type
        :informix
      end

      private

      # Informix has issues with quoted identifiers, so
      # turn off database quoting by default.
      def quote_identifiers_default
        false
      end

      # SQL fragment for showing a table is temporary
      def temporary_table_sql
        TEMPORARY
      end
    end
    
    module DatasetMethods
      SELECT_CLAUSE_METHODS = Dataset.clause_methods(:select, %w'limit distinct columns from join where having group compounds order')

      private

      # Informix does not support INTERSECT or EXCEPT
      def supports_intersect_except?
        false
      end

      def select_clause_methods
        SELECT_CLAUSE_METHODS
      end

      def select_limit_sql(sql)
        sql << " SKIP #{@opts[:offset]}" if @opts[:offset]
        sql << " FIRST #{@opts[:limit]}" if @opts[:limit]
      end
    end
  end
end
