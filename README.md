# ⚡ ZypherOS

ZypherOS has reached version 0.1.0.  This is a milestone of mine.  This marks a significant step forward in the creation of this OS which aims to be something unique in the world of linux.  It will take time to work out all the processes but ZypherOS strives to be the first distribution that is base agnostic.  This means that when I get it finished you will be able to download ZypherOS with a Arch base, Fedora base, or Debian base.  Each of those will be released on specific schedules corrosponding with the upstream releases.  This is a high bar I am setting but this is something that i have wanted to do for sometime now.  Please enjoy the journey, I am always looking for contributors to assist with making this dream a reality.  Contanct me anytime at zypher@zyphersystems.com.

v0.1.0 - Arch release

For this early build of ZyherOS I am at the stage where its a bootstrap script.  The process for installing zypherOS v0.1.0 is below:

* Download the official Arch Linux ISO.
* Boot into the Arch Linux ISO.
* When you get to the live iso command line prompt, simply run the following command:
  curl -fsSL https://zyphersystems.com/bootstrap | sh 

When you run this command it will prompt you to answer a few questions.  Those questions are below:

* Select drive.  (Curently ZypherOS will use the entire drive that you select.  There are plans in the future to add custom partitioning but as of now that option is not available.)
* Username
* Password
* Confirm Password
* Hostname
* Video driver selection (This is a temporary step for testing.  I plan to automate this by greping lspci in a future update.)
* Confirm drive format. (This option requires a capital YES.  Anything other that YES in all caps will cause the script to fail back to the command line.)
