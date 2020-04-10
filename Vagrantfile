
Vagrant.configure("2") do |config|
  JITSI_MEET_SERVER_IP = "10.0.3.10"
  IMAGE_NAME = "ubuntu/bionic64"

  def bridge_ip(number)
    ip_segments = JITSI_MEET_SERVER_IP.split('.')
    ip_segments[3] = ip_segments[3].to_i + 10 + number
    ip_segments.join('.')
  end

  config.vm.define "meet", primary: true do |config|
    config.vm.box = IMAGE_NAME
    config.vm.network "private_network", ip: JITSI_MEET_SERVER_IP
    config.vm.provider 'virtualbox' do |box|
      box.name = "jitsi-meet-server"
    end

    config.vm.provision "install-jitsi-meet", type: :shell, inline: <<-SHELL
      echo "Installing Jitsi meet main server (IP: #{JITSI_MEET_SERVER_IP})"
      sleep 5
      /vagrant/installer/install-jitsi.sh
    SHELL
  end

  1.upto(3) do |bridge_number|
    config.vm.define "bridge#{bridge_number}", autostart: false do |config|
      config.vm.box = IMAGE_NAME
      config.vm.network "private_network", ip: bridge_ip(bridge_number)
      config.vm.provider 'virtualbox' do |box|
        box.name = "jitsi-videobridge#{bridge_number}"
      end

      config.vm.provision "install-jitsi-videobridge", type: :shell, inline: <<-SHELL
        echo "Installing additional Jitsi video bridge ##{bridge_number}" \
          "(IP: #{bridge_ip(bridge_number)})"
        sleep 5
        if [ ! -s /vagrant/jitsibridgeinstallrc ]; then
          echo "Please configure the jitsibridgeinstallrc!" >&2
          exit 1
        fi
        echo "Setting up hostname according to server install..."
        (
          source "/vagrant/jitsibridgeinstallrc"
          echo "#{JITSI_MEET_SERVER_IP} ${JITSI_MEET_SERVER_DOMAIN_NAME}" >> /etc/hosts
        )
        /vagrant/installer/install-jitsi-videobridge.sh
      SHELL
    end
  end
end
