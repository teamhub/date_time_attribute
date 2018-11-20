require 'rubygems'
require 'active_support'
require 'active_support/duration'
require 'date_time_attribute/container'
require 'date_time_attribute/railtie' if defined?(Rails)

module DateTimeAttribute
  VERSION = '0.1.2'

  extend ActiveSupport::Concern

  def self.parser
    DateTimeAttribute::Container.parser
  end

  # @param val Any adapter responding to #parse
  def self.parser=(val)
    DateTimeAttribute::Container.parser = val
  end

  # @param [Symbol] attribute
  # @return [Container]
  def date_time_container(attribute)
    (@date_time_container ||= {})[attribute] ||= DateTimeAttribute::Container.new(send(attribute))
  end

  # @param [String, Symbol, Proc, nil] zone Time zone
  def in_time_zone(zone)
    case zone
    when nil
      yield
    when ActiveSupport::TimeZone, String
      old_zone = Time.zone
      Time.zone = zone
      yield(zone).tap { Time.zone = old_zone }
    when Proc, Symbol
      old_zone = Time.zone
      zone = instance_eval(&(zone.to_proc))
      Time.zone = zone
      yield(zone).tap { Time.zone = old_zone }
    else
      raise ArgumentError, "Expected timezone, got #{zone.inspect}"
    end
  end

  module ClassMethods

    # @param [Symbol] attribute Attribute name
    # @param [Hash<Symbol>] opts
    # @option opts [String, Symbol, Proc, nil] :time_zone
    def date_time_attribute(*attributes)
      opts = attributes.extract_options!
      time_zone = opts[:time_zone]

      attributes.each do |attribute|
        attribute = attribute.to_sym
        is_active_record_attribute = respond_to?(:attribute_method?) && attribute_method?(attribute)

        # ActiveRecord lazy initialization issue: https://github.com/einzige/date_time_attribute/issues/2
        if is_active_record_attribute && !@attribute_methods_generated
          define_attribute_methods
        end

        attr_accessor attribute unless method_defined?(attribute)

        define_method("#{attribute}_date") do
          in_time_zone(time_zone) do |time_zone|
            date_time_container(attribute).in_time_zone(time_zone).date
          end
        end

        alias_method "old_#{attribute}=", "#{attribute}="

        define_method("#{attribute}=") do |val|
          in_time_zone(time_zone) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            container.date_time = val
            self.send("old_#{attribute}=", container.date_time)
          end
        end

        define_method("#{attribute}_time") do
          in_time_zone(time_zone) do |time_zone|
            date_time_container(attribute).in_time_zone(time_zone).time
          end
        end

        define_method("#{attribute}_time_zone") do
          in_time_zone(time_zone) do |time_zone|
            date_time_container(attribute).in_time_zone(time_zone).time_zone
          end
        end

        define_method("#{attribute}_date=") do |val|
          in_time_zone(time_zone) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            (container.date = val).tap do
              self.send("#{attribute}=", container.date_time)
            end
          end
        end

        define_method("#{attribute}_time=") do |val|
          in_time_zone(time_zone) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)

            if val.present? && val.kind_of?(String) && val.size < 16
              if (val =~ /\A\d\d\d\d\Z/) == 0
                val = val.insert(2, ':')
              elsif (val =~ /\A\d\d\d\Z/) == 0
                val = val.insert(1, ':')
              elsif val.include?(',')
                val = val.gsub(',', ':')
              elsif val.include?('.')
                val = val.gsub('.', ':')
              end
            end

            (container.time = val).tap do
              self.send("#{attribute}=", container.date_time)
            end
          end
        end

        define_method("#{attribute}_time_zone=") do |val|
          in_time_zone(val) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            self.send("#{attribute}=", container.date_time)
            container.time_zone
          end if val
        end
      end
    end
  end
end
