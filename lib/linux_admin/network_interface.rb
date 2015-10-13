require 'ipaddr'

module LinuxAdmin
  class NetworkInterface
    include Common

    # Cached class instance variable for what distro we are running on
    @dist_class = nil

    # Gets the subclass specific to the local Linux distro
    #
    # @param test_dist [Boolean] Determines if the cached value will be reevaluated
    # @return [Class] The proper class to be used
    def self.dist_class(test_dist = false)
      @dist_class = nil if test_dist
      @dist_class ||= begin
        if [Distros.rhel, Distros.fedora].include?(Distros.local)
          NetworkInterfaceRH
        else
          NetworkInterfaceGeneric
        end
      end
    end

    class << self
      private

      alias_method :orig_new, :new
    end

    # Creates an instance of the correct NetworkInterface subclass for the local distro
    def self.new(*args)
      if self == LinuxAdmin::NetworkInterface
        dist_class.new(*args)
      else
        orig_new(*args)
      end
    end

    # @return [String] the interface for networking operations
    attr_reader :interface

    # @param interface [String] Name of the network interface to manage
    def initialize(interface)
      @interface = interface
      reload
    end

    # Gathers current network information for this interface
    def reload
      @network_conf = {}
      return false unless (ip_output = ip_show)

      parse_ip4(ip_output)
      parse_ip6(ip_output, :global)
      parse_ip6(ip_output, :link)

      @network_conf[:mac] = parse_ip_output(ip_output, %r{link/ether}, 1)

      ip_route_res = run(cmd("ip"), :params => ["route"])
      @network_conf[:gateway] = parse_ip_output(ip_route_res.output, /^default/, 2) if ip_route_res.success?
      true
    end

    # Retrieve the IPv4 address assigned to the interface
    #
    # @return [String] IPv4 address for the managed interface
    def address
      @network_conf[:address]
    end

    # Retrieve the IPv6 address assigned to the interface
    #
    # @return [String] IPv6 address for the managed interface
    # @raise [ArgumentError] if the given scope is not `:global` or `:link`
    def address6(scope = :global)
      case scope
      when :global
        @network_conf[:address6_global]
      when :link
        @network_conf[:address6_link]
      else
        raise ArgumentError, "Unrecognized address scope #{scope}"
      end
    end

    # Retrieve the MAC address associated with the interface
    #
    # @return [String] the MAC address
    def mac_address
      @network_conf[:mac]
    end

    # Retrieve the IPv4 sub-net mask assigned to the interface
    #
    # @return [String] IPv4 netmask
    def netmask
      @network_conf[:mask]
    end

    # Retrieve the IPv6 sub-net mask assigned to the interface
    #
    # @return [String] IPv6 netmask
    # @raise [ArgumentError] if the given scope is not `:global` or `:link`
    def netmask6(scope = :global)
      if scope == :global
        @network_conf[:mask6_global]
      elsif scope == :link
        @network_conf[:mask6_link]
      else
        raise ArgumentError, "Unrecognized address scope #{scope}"
      end
    end

    # Retrieve the IPv4 default gateway associated with the interface
    #
    # @return [String] IPv4 gateway address
    def gateway
      @network_conf[:gateway]
    end

    private

    # Parses the output of `ip addr show`
    #
    # @param output [String] The command output
    # @param regex  [Regexp] Regular expression to match the desired output line
    # @param col    [Fixnum] The whitespace delimited column to be returned
    # @return [String] The parsed data
    def parse_ip_output(output, regex, col)
      the_line = output.split("\n").detect { |l| l =~ regex }
      the_line.nil? ? nil : the_line.strip.split(' ')[col]
    end

    # Runs the command `ip addr show <interface>`
    #
    # @return [String] The command output, nil on failure
    def ip_show
      result = run(cmd("ip"), :params => ["addr", "show", @interface])
      result.success? ? result.output : nil
    end

    # Parses the IPv4 information from the output of `ip addr show <device>`
    #
    # @param ip_output [String] The command output
    def parse_ip4(ip_output)
      cidr_ip = parse_ip_output(ip_output, /inet/, 1)
      return unless cidr_ip

      @network_conf[:address] = cidr_ip.split('/')[0]
      @network_conf[:mask] = IPAddr.new('255.255.255.255').mask(cidr_ip.split('/')[1]).to_s
    end

    # Parses the IPv6 information from the output of `ip addr show <device>`
    #
    # @param ip_output [String] The command output
    # @param scope     [Symbol] The IPv6 scope (either `:global` or `:local`)
    def parse_ip6(ip_output, scope)
      mask_addr = IPAddr.new('ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
      cidr_ip = parse_ip_output(ip_output, /inet6 .* scope #{scope}/, 1)
      return unless cidr_ip

      parts = cidr_ip.split('/')
      @network_conf["address6_#{scope}".to_sym] = parts[0]
      @network_conf["mask6_#{scope}".to_sym] = mask_addr.mask(parts[1]).to_s
    end
  end
end

Dir.glob(File.join(File.dirname(__FILE__), "network_interface", "*.rb")).each { |f| require f }
