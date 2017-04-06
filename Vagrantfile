Vagrant.configure(2) do |config|

  config.vm.box = "bento/centos-7.2"
  config.ssh.insert_key = false

  config.vm.define "master" do |config|
    config.vm.hostname = "master"
    config.vm.network :private_network, ip: "192.168.121.9", virtualbox__intnet: "kubernetes"
  end

  config.vm.define "sv01" do |config|
    config.vm.hostname = "sv01"
    config.vm.network :private_network, ip: "192.168.121.65", virtualbox__intnet: "kubernetes"
  end

  config.vm.define "sv02" do |config|
    config.vm.hostname = "sv02"
    config.vm.network :private_network, ip: "192.168.121.66", virtualbox__intnet: "kubernetes"
  end

  config.vm.define "sv03" do |config|
    config.vm.hostname = "sv03"
    config.vm.network :private_network, ip: "192.168.121.67", virtualbox__intnet: "kubernetes"
  end

  config.vm.provider :virtualbox do |v|
    v.linked_clone = true
  end

  config.vm.provision "shell", inline: <<-SHELL
    set -eux

    # selinux
    setenforce 0 ||:
    sed -i "/^SELINUX=/c SELINUX=disabled" /etc/selinux/config

    # timezone for centos-7
    case "$(rpm -q centos-release --qf %{VERSION})" in
      7) timedatectl set-timezone Asia/Tokyo ;;
    esac

    # package
    yum -y install \
      nc vim-enhanced bash-completion lsof rsync tcpdump bridge-utils epel-release
    yum -y install colordiff jq

    # hosts
    cp -av /vagrant/files/etc/hosts /etc/hosts

    echo ok
  SHELL

end
