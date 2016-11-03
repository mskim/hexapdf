# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2016 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#++

require 'hexapdf/error'
require 'hexapdf/object'
require 'hexapdf/dictionary_fields'
require 'hexapdf/reference'

module HexaPDF

  # Implementation of the PDF dictionary type.
  #
  # Subclasses should use the available class method ::define_field to create fields according to
  # the PDF specification. This allows, among other things, automatic type checking and
  # basic validation.
  #
  # Fields defined in superclasses are inherited by their subclasses. This avoids duplicating
  # basic field information.
  #
  # See: PDF1.7 s7.3.7
  class Dictionary < HexaPDF::Object

    include DictionaryFields

    # Defines an entry for the field +name+ and returns the initalized
    # HexaPDF::DictionaryFields::Field object. A suitable converter module (see
    # HexaPDF::DictionaryFields::Field#converter) is selected based on the type argument.
    #
    # Options:
    #
    # type:: The class (or an array of classes) that a value of this field must have. Here is a
    #        mapping from PDF object types to classes:
    #
    #        Boolean::    \[TrueClass, FalseClass] (or use the Boolean constant)
    #        Integer::    Integer
    #        Real::       Float
    #        String::     String (for text strings), PDFByteString (for binary strings)
    #        Date::       PDFDate
    #        Name::       Symbol
    #        Array::      Array
    #        Dictionary:: Dictionary (or any subclass) or Hash
    #        Stream::     Stream (or any subclass)
    #        Null::       NilClass
    #
    #        If an array of classes is provided, the value can be an instance of any of these
    #        classes.
    #
    #        If a Symbol object instead of a class is provided, the class is looked up using the
    #        'object.type_map' global configuration option when necessary to support lazy loading.
    #
    # required:: Specifies whether this field is required.
    #
    # default:: Specifies the default value for the field, if any.
    #
    # indirect:: Specifies whether the value (or the values in the array value) of this field has
    #            to be an indirect object (+true+), a direct object (+false+) or if it doesn't
    #            matter (unspecified or +nil+).
    #
    # version:: Specifies the minimum version of the PDF specification needed for this value.
    def self.define_field(name, type:, required: false, default: nil, indirect: nil,
      version: '1.2')
      @fields ||= {}
      @fields[name] = Field.new(type, required, default, indirect, version)
    end

    # Returns the field entry for the given field name.
    #
    # The ancestor classes are also searched for such a field entry if none is found for the
    # current class.
    def self.field(name)
      if defined?(@fields) && @fields.key?(name)
        @fields[name]
      elsif superclass.respond_to?(:field)
        superclass.field(name)
      end
    end

    # :call-seq:
    #   class.each_field {|name, data| block }   -> class
    #   class.each_field                         -> Enumerator
    #
    # Calls the block once for each field defined either in this class or in one of the ancestor
    # classes.
    def self.each_field(&block) # :yields: name, data
      return to_enum(__method__) unless block_given?
      superclass.each_field(&block) if self != Dictionary && superclass != Dictionary
      @fields.each(&block) if defined?(@fields)
    end


    # Returns the value for the given dictionary entry.
    #
    # This method should be used instead of direct access to the value because it provides
    # numerous advantages:
    #
    # * References are automatically resolved.
    #
    # * Returns the native Ruby object for values with class HexaPDF::Object. However, all
    #   subclasses of HexaPDF::Object are returned as is (it makes no sense, for example, to return
    #   the hash that describes the Catalog instead of the Catalog object).
    #
    # * Automatically wraps hash values in specific subclasses of this class if field information is
    #   available (see ::define_field).
    #
    # * Returns the default value if one is specified and no value is available.
    def [](name)
      field = self.class.field(name)
      data = if key?(name)
               value[name]
             elsif field && field.default?
               value[name] = field.default
             end
      value[name] = data = document.deref(data) if data.kind_of?(HexaPDF::Reference)
      if data.class == HexaPDF::Object || (data.kind_of?(HexaPDF::Object) && data.value.nil?)
        data = data.value
      end
      self[name] = data = field.convert(data, document) if field && field.convert?(data)
      data
    end

    # Stores the data under name in the dictionary. Name has to be a Symbol object.
    #
    # If the current value for this name has the class HexaPDF::Object (and only this, no
    # subclasses) and the given value has not (including subclasses), the value is stored inside the
    # HexaPDF::Object.
    def []=(name, data)
      unless name.kind_of?(Symbol)
        raise ArgumentError, "Only Symbol (Name) keys are allowed to be used in PDF dictionaries"
      end

      if value[name].class == HexaPDF::Object && !data.kind_of?(HexaPDF::Object) &&
          !data.kind_of?(HexaPDF::Reference)
        value[name].value = data
      else
        value[name] = data
      end
    end

    # Returns +true+ if the given key is present in the dictionary.
    def key?(key)
      value.key?(key)
    end

    # Deletes the name-value pair from the dictionary and returns the value. If such a pair does
    # not exist, +nil+ is returned.
    def delete(name)
      value.delete(name) { nil }
    end

    # :call-seq:
    #   dict.each {|name, value| block}    -> dict
    #   dict.each                          -> Enumerator
    #
    # Calls the given block once for every name-value entry that is stored in the dictionary.
    #
    # Note that the yielded value is already preprocessed like in #[].
    def each
      return to_enum(__method__) unless block_given?
      value.each_key {|name| yield(name, self[name])}
      self
    end

    # Returns the value of the /Type field or, if not set, the result of Object#type.
    def type
      self[:Type] || super
    end

    # Returns +true+ if the dictionary contains no entries.
    def empty?
      value.empty?
    end

    # Returns a dup of the underlying hash.
    def to_hash
      value.dup
    end
    alias :to_h :to_hash


    private

    # Ensures that the value is useful for a Dictionary and updates the object's value with
    # information from the dictionary's field.
    def after_data_change # :nodoc:
      super
      data.value ||= {}
      unless value.kind_of?(Hash)
        raise ArgumentError, "A PDF dictionary object needs a hash value, not a #{value.class}"
      end
      set_required_fields_with_defaults
    end

    # Sets all required fields that have no current value but a default value to their respective
    # default value.
    def set_required_fields_with_defaults
      self.class.each_field do |name, field|
        if !key?(name) && field.required? && field.default?
          value[name] = field.default
        end
      end
    end

    # Iterates over all currently set fields and those that are required.
    def each_set_key_or_required_field #:yields: name, field
      value.each_key {|name| yield(name, self.class.field(name))}
      self.class.each_field do |name, field|
        yield(name, field) if field.required? && !value.key?(name)
      end
    end

    # Performs validation tasks based on the currently set keys and defined fields.
    def perform_validation(&block)
      super
      each_set_key_or_required_field do |name, field|
        obj = key?(name) && self[name] || nil

        # Validate nested objects
        validate_nested(obj, &block)

        # The checks below need a valid field definition
        next if field.nil?

        # Check that required fields are set
        if field.required? && obj.nil?
          yield("Required field #{name} is not set", field.default?)
          self[name] = obj = field.default
        end

        # Check if the document version is set high enough
        if field.version > document.instance_variable_get(:@version)
          yield("Field #{name} requires document version to be #{field.version}", true)
          document.version = field.version
        end

        # The checks below assume that the field has a value
        next if obj.nil?

        # Check the type of the field
        unless field.valid_object?(obj)
          yield("Type of field #{name} is invalid: #{obj.class}", false)
        end

        # Check if field value needs to be (in)direct
        unless field.indirect.nil?
          obj = value[name] # we need the unwrapped object!
          if field.indirect && (!obj.kind_of?(HexaPDF::Object) || !obj.indirect?)
            yield("Field #{name} needs to be an indirect object", true)
            value[name] = obj = document.add(obj)
          elsif !field.indirect && obj.kind_of?(HexaPDF::Object) && obj.indirect?
            yield("Field #{name} needs to be a direct object", true)
            document.delete(obj)
            value[name] = obj = obj.value
          end
        end
      end
    end

  end

end
