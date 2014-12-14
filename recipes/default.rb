if node[:ssh_keys]
  node[:ssh_keys].each do |node_user, bag_users|
    next unless node_user
    next unless bag_users

    # Getting node user data
    user = node['etc']['passwd'][node_user]

    # Defaults for new user
    user = {'uid' => node_user, 'gid' => node_user, 'dir' => "/home/#{node_user}"} unless user

    if user and user['dir'] and user['dir'] != "/dev/null"
      # Preparing SSH keys
      ssh_keys = []

      Array(bag_users).each do |bag_user|
        data = data_bag_item('users', bag_user)
        if data and data['ssh_keys']
          ssh_keys += Array(data['ssh_keys'])
        end
      end

      # Saving SSH keys
      if ssh_keys.length > 0
        symlink_file = false
        home_dir = user['dir']
        authorized_keys_file = "#{home_dir}/.ssh/authorized_keys"

        # Get realpath if symlink
        if File.symlink?(authorized_keys_file)
          Chef::Log.info("Use symlink target: #{authorized_keys_file}")
          source_authorized_keys_file = File.readlink(authorized_keys_file)
          temp_authorized_keys_file = "#{authorized_keys_file}.tmp"
          `cp #{source_authorized_keys_file} #{temp_authorized_keys_file}`
          symlink_file = true
        end

        if node[:ssh_keys_keep_existing] && File.exist?(authorized_keys_file)
          Chef::Log.info("Keep authorized keys from: #{authorized_keys_file}")

          # Loading existing keys
          File.open(authorized_keys_file).each do |line|
            if line.start_with?("ssh")
              ssh_keys += Array(line.delete "\n")
            end
          end

          ssh_keys.uniq!
        else
          # Creating ".ssh" directory
          directory "#{home_dir}/.ssh" do
            owner user['uid']
            group user['gid'] || user['uid']
            mode "0700"
          end
        end

        # Creating "authorized_keys"
        template "authorized_keys" do
          source "authorized_keys.erb"
          if symlink_file
            path temp_authorized_keys_file
          else
            path authorized_keys_file
          end
          owner user['uid']
          group user['gid'] || user['uid']
          mode "0600"
          variables :ssh_keys => ssh_keys
        end

        bash "symlink file" do
          code "cat #{temp_authorized_keys_file} > #{source_authorized_keys_file} && rm #{temp_authorized_keys_file}"
          only_if { symlink_file }
        end
      end
    end
  end
end
