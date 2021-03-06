# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2014-2017 Thomas Leitner
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

module HexaPDF
  module Task

    # Task for recursively dereferencing a single object or the reachable parts of the whole PDF
    # document. Dereferencing means that the references are replaced with the actual objects.
    #
    # Running this task is most often done to prepare for other steps in a PDF transformation
    # process.
    class Dereference

      # Recursively dereferences the reachable parts of the document and returns an array of
      # objects that are never referenced. This includes indirect objects that are used as values
      # for the /Length entry of a stream.
      #
      # If the optional argument +object+ is provided, only the given object is dereferenced and
      # nothing is returned.
      def self.call(doc, object: nil)
        new(doc, object).result
      end

      attr_reader :result # :nodoc:

      def initialize(doc, object = nil) #:nodoc:
        @doc = doc
        @object = object
        @seen = {}
        @result = nil
        execute
      end

      private

      def execute #:nodoc:
        if @object
          dereference(@object)
        else
          dereference(@doc.trailer)
          @result = []
          @doc.each(current: false) do |obj|
            if !@seen.key?(obj.data) && obj.type != :ObjStm && obj.type != :XRef
              @result << obj
            elsif obj.kind_of?(HexaPDF::Stream) && (val = obj.value[:Length]) &&
                val.kind_of?(HexaPDF::Object) && val.indirect?
              @result << val
            end
          end
        end
      end

      def dereference(object) #:nodoc:
        return object if @seen.key?(object.data)
        @seen[object.data] = true
        recurse(object.value)
        object
      end

      def recurse(val) #:nodoc:
        case val
        when Hash
          val.each {|k, v| val[k] = recurse(v)}
        when Array
          val.map! {|v| recurse(v)}
        when HexaPDF::Reference
          dereference(@doc.object(val))
        when HexaPDF::Object
          dereference(val)
        else
          val
        end
      end

    end

  end
end
