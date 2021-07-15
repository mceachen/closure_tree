module ClosureTree
  module NumericOrderSupport

    def self.adapter_for_connection(connection)
      das = WithAdvisoryLock::DatabaseAdapterSupport.new(connection)
      if das.postgresql?
        ::ClosureTree::NumericOrderSupport::PostgreSQLAdapter
      elsif das.mysql?
        ::ClosureTree::NumericOrderSupport::MysqlAdapter
      else
        ::ClosureTree::NumericOrderSupport::GenericAdapter
      end
    end

    def self.adapter_for_database_type(database_type)
      case database_type
      when :postgres
        ::ClosureTree::NumericOrderSupport::PostgreSQLAdapter
      when :mysql
        ::ClosureTree::NumericOrderSupport::MysqlAdapter
      else
        ::ClosureTree::NumericOrderSupport::GenericAdapter
      end
    end

    module MysqlAdapter
      def reorder_with_parent_id(parent_id, minimum_sort_order_value = nil)
        return if parent_id.nil? && dont_order_roots
        min_where = if minimum_sort_order_value
          "AND #{quoted_order_column} >= #{minimum_sort_order_value}"
        else
          ""
        end
        connection.execute 'SET @i = 0'
        connection.execute <<-SQL.squish
          UPDATE #{quoted_table_name}
            SET #{quoted_order_column} = (@i := @i + 1) + #{minimum_sort_order_value.to_i - 1}
          WHERE #{where_eq(parent_column_name, parent_id)} #{min_where}
          ORDER BY #{nulls_last_order_by}
        SQL
      end
    end

    module PostgreSQLAdapter
      def reorder_with_parent_id(parent_id, minimum_sort_order_value = nil)
        return if parent_id.nil? && dont_order_roots
        min_where = if minimum_sort_order_value
          "AND #{quoted_order_column} >= #{minimum_sort_order_value}"
        else
          ""
        end
        connection.execute <<-SQL.squish
          UPDATE #{quoted_table_name}
          SET #{quoted_order_column(false)} = t.seq + #{minimum_sort_order_value.to_i - 1}
          FROM (
            SELECT #{quoted_id_column_name} AS id, row_number() OVER(ORDER BY #{order_by}) AS seq
            FROM #{quoted_table_name}
            WHERE #{where_eq(parent_column_name, parent_id)} #{min_where}
          ) AS t
          WHERE #{quoted_table_name}.#{quoted_id_column_name} = t.id and
                #{quoted_table_name}.#{quoted_order_column(false)} is distinct from t.seq + #{minimum_sort_order_value.to_i - 1}
        SQL
      end

      def rows_updated(result)
        result.cmd_status.sub(/\AUPDATE /, '').to_i
      end
    end

    module GenericAdapter
      def reorder_with_parent_id(parent_id, minimum_sort_order_value = nil)
        return if parent_id.nil? && dont_order_roots
        scope = model_class.
          where(parent_column_sym => parent_id).
          order(nulls_last_order_by)
        if minimum_sort_order_value
          scope = scope.where("#{quoted_order_column} >= #{minimum_sort_order_value}")
        end
        scope.each_with_index do |ea, idx|
          ea.update_order_value(idx + minimum_sort_order_value.to_i)
        end
      end
    end
  end
end
