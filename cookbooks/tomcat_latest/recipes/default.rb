#
# Cookbook Name:: tomcat_latest
# Recipe:: default
#
# Copyright 2013, Chendil Kumar Manoharan
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

tomcat_version = node['tomcat_latest']['tomcat_version']
tomcat_install_loc=node['tomcat_latest']['tomcat_install_loc']
platform=node['platform']
platform_version=node['platform_version']
direct_download_version=node['tomcat_latest']['direct_download_version']
tomcat_user=node['tomcat_latest']['tomcat_user']



if platform=="suse" || platform=="centos" || platform=="fedora"

if direct_download_version!="na"

include_recipe "java"
if ( direct_download_version =~ /7(.*)/ ) 
  direct_download_url= "http://archive.apache.org/dist/tomcat/tomcat-7/v"+"#{direct_download_version}"+"/bin/apache-tomcat-#{direct_download_version}.tar.gz";
else if ( direct_download_version =~ /6(.*)/ )
   direct_download_url= "http://archive.apache.org/dist/tomcat/tomcat-6/v"+"#{direct_download_version}"+"/bin/apache-tomcat-#{direct_download_version}.tar.gz";
else 
	abort("Unsupported tomcat version "+"#{direct_download_version}"+"specified")
	end
end

script "Download Apache Tomcat #{direct_download_version}" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH
  wget "#{direct_download_url}" -O "/tmp/apache-tomcat-#{direct_download_version}.tar.gz"
  mkdir -p #{tomcat_install_loc}/tomcat
  EOH
end

execute "Unzip Apache Tomcat binary file" do
 user "#{tomcat_user}"
 installation_dir = "/tmp"
 cwd installation_dir
 command "tar zxvf /tmp/apache-tomcat-* -C #{tomcat_install_loc}/tomcat" 
 action :run
end


execute "Change the directory name to apache-tomcat" do
 user "#{tomcat_user}"
 cwd #{tomcat_install_loc}/tomcat
 command "cd #{tomcat_install_loc}/tomcat; mv apache-tomcat-* apache-tomcat"
 action :run
end


   
 template "#{tomcat_install_loc}/tomcat/apache-tomcat/conf/server.xml" do
  source "server6.xml.erb"
  owner "#{tomcat_user}"
  mode "0644"  
end
template "/etc/rc.d/tomcat" do
  source "tomcat.erb"
  owner "#{tomcat_user}"
  mode "0755"  
end
if platform=="suse" 

script "Start tomcat" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH  
  /etc/init.d/tomcat start
  EOH
end
end
if platform=="centos" || platform=="fedora"

script "Start tomcat" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH  
  /etc/rc.d/tomcat start
  EOH
end
end
end
if direct_download_version=="na"


include_recipe "java"

#convert version number to a string if it isn't already
if tomcat_version.instance_of? Fixnum
  tomcat_version = tomcat_version.to_s
end

case tomcat_version
when "6"
tomcat_url = node['tomcat_latest']['tomcat_url_6']
script "Download Apache Tomcat 6 " do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH
  wget #{tomcat_url} -O /tmp/tomcat_pag.txt
  url=`grep -m 1 apache-tomcat-6.*.[0-9][0-9].tar.[g][z] /tmp/tomcat_pag.txt | cut -d '"' -f 2`
  wget $url 
  mkdir -p #{tomcat_install_loc}/tomcat6
  EOH
end

execute "Unzip Apache Tomcat 6 binary file" do
 user "#{tomcat_user}"
 installation_dir = "/tmp"
 cwd installation_dir
 command "tar zxvf /tmp/apache-tomcat-6.*.tar.gz -C #{tomcat_install_loc}/tomcat6" 
 action :run
end
execute "Change the directory name to apache-tomcat-6" do
 user "#{tomcat_user}" 
 cwd #{tomcat_install_loc}/tomcat6
 command "cd #{tomcat_install_loc}/tomcat6; mv apache-tomcat-6.* apache-tomcat-6"
 action :run
end


template "#{tomcat_install_loc}/tomcat6/apache-tomcat-6/conf/server.xml" do
  source "server6.xml.erb"
  owner "#{tomcat_user}"
  mode "0644"  
end
template "/etc/rc.d/tomcat6" do
  source "tomcat6.erb"
  owner "#{tomcat_user}"
  mode "0755"  
end

if platform=="suse" 

script "Start tomcat 6" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH  
  /etc/init.d/tomcat6 start
  EOH
end
end
if platform=="centos" || platform=="fedora"

script "Start tomcat 6" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH  
  /etc/rc.d/tomcat6 start
  EOH
end
end

when "7"
tomcat_url = node['tomcat_latest']['tomcat_url_7']
script "Download Apache Tomcat 7 " do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH
  wget #{tomcat_url} -O /tmp/tomcat_pag.txt
  url=`grep -m 1 apache-tomcat-7.*.[0-9][0-9].tar.[g][z] /tmp/tomcat_pag.txt | cut -d '"' -f 2`
  wget $url 
  mkdir -p #{tomcat_install_loc}/tomcat7
  EOH
end

execute "Unzip Apache Tomcat 7 binary file" do
 user "#{tomcat_user}"
 installation_dir = "/tmp"
 cwd installation_dir
 command "tar zxvf /tmp/apache-tomcat-7.*.tar.gz -C #{tomcat_install_loc}/tomcat7" 
 action :run
end


execute "Change the directory name to apache-tomcat-7" do
 user "#{tomcat_user}"
 cwd #{tomcat_install_loc}/tomcat7
 command "cd #{tomcat_install_loc}/tomcat7; mv apache-tomcat-7.* apache-tomcat-7"
 action :run
end


template "#{tomcat_install_loc}/tomcat7/apache-tomcat-7/conf/server.xml" do
  source "server7.xml.erb"
  owner "#{tomcat_user}" 
  mode "0644"  
end
template "/etc/rc.d/tomcat7" do
  source "tomcat7.erb"
  owner "#{tomcat_user}" 
  mode "0755"  
end



if platform=="suse" 

script "Start tomcat 7" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH  
  sudo /etc/init.d/tomcat7 start
  EOH
end
end
if platform=="centos" || platform == "fedora"

script "Start tomcat 7" do
  interpreter "bash"
  user "#{tomcat_user}"
  cwd "/tmp"
  code <<-EOH  
  sudo /etc/rc.d/tomcat7 start
  EOH
end

end

end

# else 
# log "#{platform} #{platform_version} is not yet supported." do
	# #message "#{platform} #{platform_version} is not yet supported."
  # level :info
# end
end




end
