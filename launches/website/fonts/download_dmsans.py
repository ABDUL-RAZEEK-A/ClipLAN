import urllib.request
import ssl
import json
import os
import re

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

CSS_URL = "https://fonts.googleapis.com/css2?family=DM+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap"

req = urllib.request.Request(CSS_URL, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'})
css_response = urllib.request.urlopen(req, context=ctx).read().decode('utf-8')

urls = re.findall(r'url\((https://[^)]+)\)', css_response)

if not os.path.exists("DM_Sans"):
    os.makedirs("DM_Sans")

for idx, url in enumerate(set(urls)):
    filename = f"DM_Sans/dmsans_{idx}.woff2"
    print(f"Downloading {filename}")
    font_data = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), context=ctx).read()
    with open(filename, 'wb') as f:
        f.write(font_data)
    css_response = css_response.replace(url, f"DM_Sans/dmsans_{idx}.woff2")

with open("fonts.css", "a") as f:
    f.write("\n\n/* DM Sans */\n")
    f.write(css_response)

print("DM Sans downloaded.")
