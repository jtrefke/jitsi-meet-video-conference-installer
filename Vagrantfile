
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"
  config.vm.network "private_network", ip: "10.0.3.33"
  config.vm.provider 'virtualbox' do |box|
    box.name = 'jitsi-meet'
  end

  config.vm.provision "install-jitsi", type: :shell, inline: <<-SHELL
    cd /vagrant

    if [ ! -s "./jitsiinstallrc" ]; then
      echo "Ensure to set up a jitsiinstallrc file before install!" >&2
      exit 1
    fi
    ./installer/install-jitsi.sh
  SHELL
end
