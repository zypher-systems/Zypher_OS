# ⚡ ZypherOS

ZypherOS has reached version 0.1.0.  This is a milestone of mine.  This marks a significant step forward in the creation of this OS which aims to be something unique in the world of linux.  It will take time to work out all the processes but ZypherOS strives to be the first distribution that is base agnostic.  This means that when I get it finished you will be able to download ZypherOS with a Arch base, Fedora base, or Debian base.  Each of those will be released on specific schedules corrosponding with the upstream releases.  This is a high bar I am setting but this is something that i have wanted to do for sometime now.  Please enjoy the journey, I am always looking for contributors to assist with making this dream a reality.  Contanct me anytime at zypher@zyphersystems.com.

v0.1.0 - Arch release

Requirements:
* A based arch install with:
* KDE Plasma desktop
* limine bootloader
* sddm greater

Once the system is installed simply install the early version of ZypherOS with one of the below methods.  As always thanks for testing.

```bash
git clone [https://github.com/zypher-systems/Zypher_OS.git](https://github.com/zypher-systems/Zypher_OS.git)
cd Zypher_OS
chmod +x install.sh subscripts/*.sh
./install.sh

Or use a single command to kick off the install: 

curl -fsSL https://zyphersystems.com/install | sh
