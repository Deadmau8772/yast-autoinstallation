# Copyright (c) [2018] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "forwardable"

module Y2Autoinstallation
  module AutoinstIssues
    # List of general AutoYaST problems
    #
    # @example Registering some problems
    #   list = List.new
    #   list.add(:invalid_value, "firewall", "interfaces",
    #     "eth0",
    #     _("This interface has been defined for more than one zone."))
    #
    # @example Iterating through the list of problems
    #   list.map(&:severity) #=> [:warn]
    class List
      include Yast::Logger
      include Enumerable
      extend Forwardable

      def_delegators :@items, :each, :empty?, :<<

      # Constructor
      def initialize
        @items = []
      end

      # Add a problem to the list
      #
      # The type of the problem is identified as a symbol which name is the
      # underscore version of the class which implements it.  For instance,
      # `InvalidValue` would be referred as `:invalid_value`.
      #
      # If a given type of problem requires some additional arguments, they
      # should be added when calling this method. See the next example.
      #
      # @example Adding a problem with additional arguments
      #   list = List.new
      #   list.add(:invalid_value, "firewall", "FW_DEV_INT", "1",
      #     _("Is not supported anymore."))
      #   list.empty? #=> false
      #
      # @param type       [Symbol] Issue type
      # @param extra_args [Array] Additional arguments for the given problem
      # @return [Array<Issue>] List of problems
      def add(type, *extra_args)
        class_name = type.to_s.split("_").map(&:capitalize).join
        klass = Y2Autoinstallation::AutoinstIssues.const_get(class_name)
        self << klass.new(*extra_args)
      end

      # Determine whether any of the problem on the list is fatal
      #
      # @return [Boolean] true if any of them is a fatal problem
      def fatal?
        any?(&:fatal?)
      end

      # Returns an array containing registered problems
      #
      # @return [Array<Issue>] List of problems
      def to_a
        @items
      end
    end
  end
end
