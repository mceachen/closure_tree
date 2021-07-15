require 'closure_tree/support_flags'
require 'closure_tree/support_attributes'
require 'closure_tree/numeric_order_support'
require 'closure_tree/active_record_support'
require 'closure_tree/hash_tree_support'
require 'with_advisory_lock'

# This class and mixins are an effort to reduce the namespace pollution to models that act_as_tree.
module ClosureTree
  class Support
    include ClosureTree::SupportFlags
    include ClosureTree::SupportAttributes
    include ClosureTree::ActiveRecordSupport
    include ClosureTree::HashTreeSupport

    attr_reader :model_class
    attr_reader :options

    def initialize(model_class, options)
      @model_class = model_class
      @options = {
        :parent_column_name => 'parent_id',
        :dependent => :nullify, # or :destroy or :delete_all -- see the README
        :name_column => 'name',
        :with_advisory_lock => true,
        :numeric_order => false
      }.merge(options)
      raise ArgumentError, "name_column can't be 'path'" if options[:name_column] == 'path'
      if order_is_numeric?
        database_type = database_type_from_options || database_type_from_connection
        extend NumericOrderSupport.adapter_for_database_type(database_type)
      end
    end

    def hierarchy_class_for_model
      parent_class = ActiveSupport::VERSION::MAJOR >= 6 ? model_class.module_parent : model_class.parent
      hierarchy_class = parent_class.const_set(short_hierarchy_class_name, Class.new(ActiveRecord::Base))
      use_attr_accessible = use_attr_accessible?
      include_forbidden_attributes_protection = include_forbidden_attributes_protection?
      model_class_name = model_class.to_s
      hierarchy_class.class_eval do
        include ActiveModel::ForbiddenAttributesProtection if include_forbidden_attributes_protection
        belongs_to :ancestor, class_name: model_class_name
        belongs_to :descendant, class_name: model_class_name
        attr_accessible :ancestor, :descendant, :generations if use_attr_accessible
        def ==(other)
          self.class == other.class && ancestor_id == other.ancestor_id && descendant_id == other.descendant_id
        end
        alias :eql? :==
        def hash
          ancestor_id.hash << 31 ^ descendant_id.hash
        end
      end
      hierarchy_class.table_name = hierarchy_table_name
      hierarchy_class
    end

    def hierarchy_table_name
      # We need to use the table_name, not something like ct_class.to_s.demodulize + "_hierarchies",
      # because they may have overridden the table name, which is what we want to be consistent with
      # in order for the schema to make sense.
      tablename = options[:hierarchy_table_name] ||
        remove_prefix_and_suffix(table_name).singularize + "_hierarchies"

      ActiveRecord::Base.table_name_prefix + tablename + ActiveRecord::Base.table_name_suffix
    end

    def with_order_option(opts)
      if order_option?
        opts[:order] = [opts[:order], order_by].compact.join(",")
      end
      opts
    end

    def scope_with_order(scope, additional_order_by = nil)
      if order_option?
        scope.order(*([additional_order_by, order_by].compact))
      else
        additional_order_by ? scope.order(additional_order_by) : scope
      end
    end

    def belongs_to_with_optional_option(opts)
      ActiveRecord::VERSION::MAJOR < 5 ? opts.except(:optional) : opts
    end

    # lambda-ize the order, but don't apply the default order_option
    def has_many_order_without_option(order_by_opt)
      [lambda { order(order_by_opt.call) }]
    end

    def has_many_order_with_option(order_by_opt=nil)
      order_options = [order_by_opt, order_by].compact
      [lambda {
        order_options = order_options.map { |o| o.is_a?(Proc) ? o.call : o }
        order(order_options)
      }]
    end

    def ids_from(scope)
      scope.pluck(model_class.primary_key)
    end

    def where_eq(column_name, value)
      if value.nil?
        "#{connection.quote_column_name(column_name)} IS NULL"
      else
        "#{connection.quote_column_name(column_name)} = #{quoted_value(value)}"
      end
    end

    def with_advisory_lock(&block)
      if options[:with_advisory_lock]
        model_class.with_advisory_lock(advisory_lock_name) do
          transaction { yield }
        end
      else
        yield
      end
    end

    def build_ancestry_attr_path(path, attributes)
      path = path.is_a?(Array) ? path.dup : [path]
      unless path.first.is_a?(Hash)
        if subclass? && has_inheritance_column?
          attributes = attributes.with_indifferent_access
          attributes[inheritance_column] ||= self.sti_name
        end
        path = path.map { |ea| attributes.merge(name_column => ea) }
      end
      path
    end

    def scoped_attributes(scope, attributes, target_table = model_class.table_name)
      table_prefixed_attributes = Hash[
        attributes.map do |column_name, column_value|
          ["#{target_table}.#{column_name}", column_value]
        end
      ]
      scope.where(table_prefixed_attributes)
    end

    def max_join_tables
      # MySQL doesn't support more than 61 joined tables (!!):
      50
    end

    def find_by_large_path(path, attributes = {}, parent_id = nil)
      next_parent_id = parent_id
      child = nil
      path.in_groups(max_join_tables, false).each do |subpath|
        child = model_class.find_by_path(subpath, attributes, next_parent_id)
        return nil if child.nil?
        next_parent_id = child._ct_id
      end
      child
    end

    def creator_class(model_class, sti_class)
      if sti_class.present?
        base_class.send(:find_sti_class, sti_class)
      else
        model_class
      end
    end

    def create(model_class, attributes)
      creator_class(model_class, attributes.with_indifferent_access[inheritance_column]).new(attributes)
    end

    def create!(model_class, attributes)
      create(model_class, attributes).tap { |ea| ea.save! }
    end

    def database_type_from_connection
      das = WithAdvisoryLock::DatabaseAdapterSupport.new(connection)
      if das.postgresql?
        :postgres
      elsif das.mysql?
        :mysql
      else
        :generic
      end
    end
  end
end
