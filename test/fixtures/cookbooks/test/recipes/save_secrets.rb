#TODO: Replace with chef vault or similar. Non-encrypted databags == bad.
require 'json'
require 'net/ssh'
require 'base64'

chef_ingredient 'chefdk'

package 'git'

directory "#{node['chef_server']['install_dir']}/chef_installer/.chef/" do
  action :create
  recursive true
end

file "#{node['chef_server']['install_dir']}/chef_installer/.chef/knife.rb" do
  content "
node_name                \"delivery\"
client_key               \"#{node['chef_server']['install_dir']}/delivery.pem\"
chef_server_url          \"https://#{node['chef_server']['fqdn']}/organizations/delivery\"
cookbook_path            [\"#{node['chef_server']['install_dir']}/chef_installer/cookbooks\"]
ssl_verify_mode          :verify_none
"
end

builder_key = OpenSSL::PKey::RSA.new(2048)

directory "#{node['chef_server']['install_dir']}/chef_installer/data_bags"

ruby_block 'write_automate_databag' do
  block do
    automate_db_item = {
      'id' => 'automate',
      'validator_pem' => ::File.read("#{node['chef_server']['install_dir']}/delivery-validator.pem"),
      'user_pem' => ::File.read("#{node['chef_server']['install_dir']}/delivery.pem"),
      'builder_pem' => builder_key.to_pem,
      'builder_pub' => "ssh-rsa #{[builder_key.to_blob].pack('m0')}",
      'license_file' => Base64.encode64(::File.read('/var/opt/delivery/license/delivery.license'))
    }
    ::File.write("#{node['chef_server']['install_dir']}/chef_installer/data_bags/automate.json", automate_db_item.to_json)
  end
  not_if { ::File.exist?("#{node['chef_server']['install_dir']}/chef_installer/data_bags/automate.json") }
end

execute 'upload databag' do
  command 'knife data bag create automate;knife data bag from file automate data_bags/automate.json'
  cwd "#{node['chef_server']['install_dir']}/chef_installer"
end

execute 'upload cookbooks' do
  command 'berks install;berks upload --no-ssl-verify'
  cwd "#{node['chef_server']['install_dir']}/chef_installer"
end
