require "mongoid"
require "mongoid/multitenancy/document"
require "mongoid/multitenancy/version"
require "mongoid/validators/tenant_validator"
if Mongoid::VERSION.start_with? '4'
  require "bson/object_id"
else
  require "moped/bson/object_id"
end

module Mongoid
  module Multitenancy
    class << self

      # Returns true if using Mongoid 4
      def mongoid4?
        Mongoid::VERSION.start_with? '4'
      end

      # Set the current tenant. Make it Thread aware
      # This sets a single tenant for primary (creation)
      # as well as scoping (search/delete) purposes
      def current_tenant=(tenant)
        self.reset.set_tenants tenant
      end

      # Returns the current tenant
      def current_tenant(klass=nil)
        if klass
          tenant_map[klass.to_s][:current_tenant]
        else
          tenant_map.first[1][:current_tenant]
        end
      end

      # Returns the scoping tenant for a tenant class
      def scoping_tenants(klass=nil)
        if klass
          tenant_map[klass.to_s][:scoping_tenants]
        else
          tenant_map.first[1][:scoping_tenants]
        end
      end

      # Returns the complete hash of tenants
      # {
      #   "Klass1" => {
      #     current_tenant: instance,
      #     scoping_tenants: [id1, id2, id3, ...]
      #   },
      #   "Klass2" => {
      #     current_tenant: instance,
      #     scoping_tenants: [id1, id2, id3, ...]
      #   },
      #   ...
      # }
      def tenant_map
        Thread.current[:mongoid_multitenancy]
      end

      # set current tenant_map 
      def tenant_map=(hash)
        Thread.current[:mongoid_multitenancy] = hash
      end

      # set current tenant_map to empty i.e. {}
      # returns self to allow chaining
      # as Mongoid::Multitenancy.reset.set_tenants .....
      def reset
        tenant_map = {}
        self
      end

      # set primary and secondary tentants in a Thread aware container
      # Primary tenant is the the one used for creation and validations
      # The combined list of Secondary tenants + Primary tenant is used
      # for the scoping purposes (search/delete)
      def set_tenants(primary_tenant, *secondary_tenants)
        klass = nil
        real_primary_tenant = nil

        # set klass based on first argument
        if primary_tenant.is_a?(Mongoid::Document)
          klass = primary_tenant.class.to_s
          real_primary_tenant = primary_tenant
        elsif primary_tenant.kind_of?(Class)
          klass = primary_tenant.to_s
        else
          raise ArgumentError.new("First argument to Mongoid::Multitenancy.set_tenants must be a Document instance OR a Document class")
        end

        tenant_map[klass] = {
          current_tenant: real_primary_tenant,
          scoping_tenants: nil
        }
        scoping_tenants = []
        secondary_tenants.each do |t|
          if t.class == Mongoid::Criteria
            t.each do |o|
              scoping_tenants << get_oid(o)
            end
          else
            scoping_tenants << get_oid(t)
          end
        end

        if real_primary_tenant && !scoping_tenants.include?(real_primary_tenant.id)
          tenant_map[klass][:scoping_tenants] = (scoping_tenants << real_primary_tenant.id)
        elsif !scoping_tenants.empty?
          tenant_map[klass][:scoping_tenants] = scoping_tenants
        end
      end

      # Affects a tenant temporary for a block execution
      def with_tenant(tenant, &block)
        if block.nil?
          raise ArgumentError, "block required"
        end

        old_tenant_map = self.tenant_map

        # reset current tenant_map and set new tenant
        self.reset
        self.set_tenants if tenant
        block.call

        self.tenant_map = old_tenant_map
      end

      private

      def is_oid?(id)
        if mongoid4?
            BSON::ObjectId.legal? id
        else
            Moped::BSON::ObjectId.legal? id
        end
      end

      def get_oid(obj)
        if is_oid?(obj)
          obj
        else
          obj.id
        end
      end

    end
  end
end
