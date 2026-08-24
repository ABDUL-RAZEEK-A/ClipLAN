import urllib.request
import re
import os
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

url = "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&family=Outfit:wght@400;500;600;700;800;900&display=swap"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'})
with urllib.request.urlopen(req) as response:
    css = response.read().decode('utf-8')

os.makedirs('fonts', exist_ok=True)
urls = re.findall(r'url\((https://[^)]+)\)', css)

for i, font_url in enumerate(urls):
    font_name = f'font_{i}.woff2'
    urllib.request.urlretrieve(font_url, os.path.join('fonts', font_name))
    css = css.replace(font_url, f'fonts/{font_name}')

with open('fonts.css', 'w') as f:
    f.write(css)
print("Done!")
