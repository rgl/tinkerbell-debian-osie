# to make sure the nodes are created sequentially, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

# enable typed triggers.
# NB this is needed to modify the libvirt domain scsi controller model to virtio-scsi.
ENV['VAGRANT_EXPERIMENTAL'] = 'typed_triggers'

require 'open3'

Vagrant.configure('2') do |config|
  config.vm.provider :libvirt do |lv, config|
    lv.memory = 2048
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = false
    lv.keymap = 'pt'
    lv.disk_bus = 'scsi'
    lv.disk_device = 'sda'
    lv.disk_driver :discard => 'unmap', :cache => 'unsafe'
    # NB vagrant-libvirt does not yet support urandom; but since tinkerbell
    #    built iPXE takes too much time to leave the "Initialising devices"
    #    phase we modify this to urandom in the trigger bellow.
    lv.random :model => 'random'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs', nfs_version: '4.2', nfs_udp: false
    config.trigger.before :'VagrantPlugins::ProviderLibvirt::Action::StartDomain', type: :action do |trigger|
      trigger.ruby do |env, machine|
        # modify the random model to use the urandom backend device.
        stdout, stderr, status = Open3.capture3(
          'virt-xml', machine.id,
          '--edit',
          '--rng', '/dev/urandom')
        if status.exitstatus != 0
          raise "failed to run virt-xml to modify the random backend device. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
        end
      end
    end
  end

  config.vm.define :builder do |config|
    config.vm.box = 'debian-11-amd64'
    config.vm.hostname = 'builder'
    config.vm.provider :libvirt do |lv, config|
      config.trigger.before :'VagrantPlugins::ProviderLibvirt::Action::StartDomain', type: :action do |trigger|
        trigger.ruby do |env, machine|
          # modify the scsi controller model to virtio-scsi.
          # see https://github.com/vagrant-libvirt/vagrant-libvirt/pull/692
          # see https://github.com/vagrant-libvirt/vagrant-libvirt/issues/999
          stdout, stderr, status = Open3.capture3(
            'virt-xml', machine.id,
            '--edit', 'type=scsi',
            '--controller', 'model=virtio-scsi')
          if status.exitstatus != 0
            raise "failed to run virt-xml to modify the scsi controller model. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
          end
        end
      end
    end
    config.vm.provision :shell, path: 'provision-builder.sh'
    config.vm.provision :shell, path: 'build.sh', env: {
      'LB_BUILD_ARCH' => ENV['LB_BUILD_ARCH'] || 'amd64',
    }
  end

  ['bios', 'uefi'].each do |firmware|
    config.vm.define firmware do |config|
      config.vm.box = nil
      config.vm.provider :libvirt do |lv, config|
        lv.loader = '/usr/share/ovmf/OVMF.fd' if firmware == 'uefi'
        lv.boot 'cdrom'
        lv.storage :file, :device => :cdrom, :path => "#{Dir.pwd}/tinkerbell-debian-osie-amd64.iso"
        lv.mgmt_attach = false
        lv.graphics_type = 'spice'
        lv.video_type = 'qxl'
        lv.input :type => 'tablet', :bus => 'usb'
        lv.channel :type => 'unix', :target_name => 'org.qemu.guest_agent.0', :target_type => 'virtio'
        lv.channel :type => 'spicevmc', :target_name => 'com.redhat.spice.0', :target_type => 'virtio'
        config.vm.synced_folder '.', '/vagrant', disabled: true
      end
    end
  end
end
