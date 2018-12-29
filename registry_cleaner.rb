#!/usr/bin/env ruby

require 'net/http'
require 'openssl'
require 'json'
require 'optparse'

DEFAULT_PORT = 5000
LEAVE_TAGS = 5

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ./registry_cleaner.rb [options]"

  opts.on('-r', '--repository NAME', 'Registry repository name') { |v| options[:repository] = v }
  opts.on('-t', '--tags_count COUNT', 'How many tags to leave') { |v| options[:leave_tags] = v.to_i }
  opts.on('-h', '--host NAME', 'Registry host name, required') { |v| options[:host] = v }
  opts.on('-p', '--port PORT', 'Registry port') { |v| options[:port] = v }
  opts.on('-al', '--auth_login LOGIN', 'Basic auth login') { |v| options[:basic_auth_login] = v }
  opts.on('-ap', '--auth_password PASSWORD', 'Basic auth login') { |v| options[:basic_auth_password] = v }
end.parse!

raise OptionParser::MissingArgument.new('host') if options[:host].nil?
options[:port] = DEFAULT_PORT if options[:port].nil?
options[:leave_tags] = LEAVE_TAGS if options[:leave_tags].nil?

uri = URI("#{options[:host]}:#{options[:port]}")

def network_request(local_uri, method: :get, headers: {}, options: {})
    Net::HTTP.start(local_uri.host, local_uri.port, use_ssl: local_uri.scheme == 'https',  verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        method_class = case method
        when :get 
            Net::HTTP::Get
        when :delete 
            Net::HTTP::Delete
        else
            raise ArgumentError.new('Unspopported request method')
        end

        request = method_class.send('new', local_uri.request_uri)
        headers.each{ |name, value| request[name] = value } if headers.any?

        unless options[:basic_auth_login].nil? && options[:basic_auth_password].nil?
            request.basic_auth options[:basic_auth_login], options[:basic_auth_password]
        end

        return http.request request
    end
end

def network_get_request(local_uri, options, headers: {})
    network_request(local_uri, options: options, headers: headers)
end

def network_delete_request(local_uri, options, headers: {})
    network_request(local_uri, method: :delete, options: options, headers: headers)
end

def get_manifest(uri, repository, tag, options)
    uri.path = "/v2/#{repository}/manifests/#{tag}"
    network_get_request(uri, options, headers: { 'Accept': 'application/vnd.docker.distribution.manifest.v2+json' })
end

def remove_manifest(uri, repository, manifest)
    uri.path = "/v2/#{repository}/manifests/#{manifest}"
    network_delete_request(uri, headers: { 'Accept': 'application/vnd.docker.distribution.manifest.v2+json' })
end

def registry_response_tags(response)
    result = {}

    unless response.nil?
        begin
            json = JSON.parse(response)
            if !json['tags'].nil? && json['tags'].any?
                json['tags'].each do |tag|
                    category = tag.gsub(/[\d]/, '')
                    result[category] = [] if result[category].nil?
                    result[category].push(tag) 
                end

                result.keys.each{ |category_name| result[category_name].sort_by!{ |t| t.gsub(/[^\d]/, '').to_i } }
            end
          rescue JSON::ParserError => e  
            puts "Can't parse JSON: #{e}"
          end
    end

    result
end

def process_repository(uri, repository, leave_tags, options)
    uri.path = "/v2/#{repository}/tags/list"

    response = network_get_request(uri, options)
    if response.code.to_i == 200
        tags_categories = registry_response_tags(response.body)
        if tags_categories.count > 0
            tags_categories.each do |category, tags|
                if tags.count > leave_tags 
                    tags_to_delete = tags[0...-leave_tags]
                    puts "Tags to delete in category `#{category}`: #{tags_to_delete.join(', ')}"
        
                    tags_to_delete.each do |tag|

                        manifest_response = get_manifest(uri, repository, tag, options)
                        manifest = manifest_response['Docker-Content-Digest']
                        unless manifest.nil?
                            puts "\t#{repository}:#{tag} removing manifest #{manifest}"
                            remove_manifest(uri, repository, manifest)
                        end
                    end
                else
                    "Not enough versions for #{repository}"
                end
            end
        else
            puts "No tags categories for #{repository}"
        end
    else
        puts "Wrong response with http code #{response.code}"
    end

    puts 'Complete'
end

def list_repositories(uri, options)
    uri.path = "/v2/_catalog"
    response = network_get_request(uri, options, headers: { 'Accept': 'application/vnd.docker.distribution.manifest.v2+json' })

    if response.nil?
        puts "Wrong result while listing repositories"
    else
        begin
            json = JSON.parse(response.body)
            if json['repositories'].any?
                json['repositories'].each{ |repo| puts "\t#{repo}" }
            else
                puts "No repositories available"
            end
          rescue JSON::ParserError => e  
            puts "Can't parse JSON: #{e}"
          end
    end
end

if options[:repository].nil?
    list_repositories(uri, options)
else
    process_repository(uri, options[:repository], options[:leave_tags], options)
end