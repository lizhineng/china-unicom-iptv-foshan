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

## Roadmap

- [x] Authenticate with IPTV server
- [x] Build playlist file .M3U8
- [x] Resolve TV channel logos
- [x] Build EPG file
- [ ] Find the password for the authinfo payload
