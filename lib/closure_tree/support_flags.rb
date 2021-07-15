module ClosureTree
  module SupportFlags

    def use_attr_accessible?
      defined?(ActiveModel::MassAssignmentSecurity) &&
        model_class.respond_to?(:accessible_attributes) &&
        ! model_class.accessible_attributes.empty?
    end

    def include_forbidden_attributes_protection?
      defined?(ActiveModel::ForbiddenAttributesProtection) &&
        model_class.ancestors.include?(ActiveModel::ForbiddenAttributesProtection)
    end

    def order_option?
      order_by.present?
    end

    def order_is_numeric?
      options[:numeric_order]
    end

    def subclass?
      model_class != model_class.base_class
    end

    def has_inheritance_column?(hash = columns_hash)
      hash.with_indifferent_access.include?(model_class.inheritance_column)
    end

    def has_name?
      model_class.new.attributes.include? options[:name_column]
    end

    def database_type_from_options
      options[:database_type]
    end
  end
end
