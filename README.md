# ⚡ ZypherOS

ZypherOS has reached version 0.1.0.  This is a milestone of mine.  This marks a significant step forward in the creation of this OS which aims to be something unique in the world of linux.  It will take time to work out all the processes but ZypherOS strives to be the first distribution that is base agnostic.  This means that when I get it finished you will be able to download ZypherOS with a Arch base, Fedora base, or Debian base.  Each of those will be released on specific schedules corrosponding with the upstream releases.  This is a high bar I am setting but this is something that i have wanted to do for sometime now.  Please enjoy the journey, I am always looking for contributors to assist with making this dream a reality.  Contanct me anytime at zypher@zyphersystems.com.

v0.1.0 - Arch release (additional release are in planning)

For this early build of ZyherOS I am at the stage where its a bootstrap script.  The process for installing zypherOS v0.1.0 is below:

* ZypherOS Alpha v0.1.0 has been released.  The ISO installer can be found at the link below:


* https://github.com/zypher-systems/Zypher_OS/releases/tag/v0.1.0-alpha



* This is our first build so there are bugs and refinements that will continue to happen throughout the development process.  When the ISO boots there are a series of events that take place.

* The installer will auto launch, if for some reason it fails, you can manually launch the installer by running ./install.sh 

* The first step in the install process is asking you some basic information.  Those steps are below:

* First you will be asked what drive you would like to install ZypherOS on. (Note: This will partition and use your entire drive.  It will format it as btrfs and setup your subvolumes for you.  At this time custom partitioning is not supported in the installer.  That will come at a later build.)

* Once you select a drive, the installer will check your network connection.  It will ping arch.org and if successful you can continue.  If not successful it will laucn nmtui to configure your wireless connection. (Note: A fully configurable network configuration will be available in a later build.)

* You will be asked for your username, password, and then a confirmation will show up asking if you are sure you want to format your hdd.  Once confirmed the rest of the installation is automated.  Once completed it will let you know then reboot.
