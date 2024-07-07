# Ditch your clunky, ad-filled TV box!

IPTV toolkit for China Unicom IPTV users in Foshan, China.

The script will help you stream IPTV from the devices you love, instead of
using the ISP's TV box, which is full of commercials and has a sluggish user
experience.

IPTV authentication varies from region to region, so just because it works in
my region doesn't mean it will work in yours. Feel free to adapt the script to
your needs.

Please note that you will need to set up the udpxy service on your router to
handle the multicast packets. After you have created the playlist file, you can
deploy it on your local server or simply import the playlist into your player.

## Usage

```bash
Usage: iptv.sh [COMMAND] [OPTIONS]

Commands:
  make:playlist     Make a playlist file
  make:epg          Make an EPG file
  decrypt:authinfo  Find a possible IPTV key

Run 'iptv.sh COMMAND -h' for help on a specific command.
```

⚡️ Download the decryptor writtern in Rust for maximum performance to find
a possible key for the `authinfo` from the [release](https://github.com/lizhineng/china-unicom-iptv-foshan/releases)
page.
