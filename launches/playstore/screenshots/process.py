import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

OUTPUT_DIR = "final"
if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

# Mapping of specific filenames to titles and subtitles
SCREENS = {
    "WhatsApp Image 2026-08-21 at 16.01.46.jpeg": {
        "title": "Discover Nearby Devices",
        "subtitle": "Instantly find and connect with devices on your network.",
        "filename": "01_Discover_Nearby_Devices.png"
    },
    "WhatsApp Image 2026-08-21 at 16.03.41.jpeg": {
        "title": "Lightning Fast Transfers",
        "subtitle": "Share large files at blazing fast speeds.",
        "filename": "02_Lightning_Fast_Transfers.png"
    },
    "WhatsApp Image 2026-08-21 at 16.01.47.jpeg": {
        "title": "Secure File Sharing",
        "subtitle": "Accept or decline incoming transfers with ease.",
        "filename": "03_Secure_File_Sharing.png"
    },
    "WhatsApp Image 2026-08-21 at 16.01.49 (1).jpeg": {
        "title": "Transfer History",
        "subtitle": "Keep track of all your sent and received files.",
        "filename": "04_Transfer_History.png"
    },
    "WhatsApp Image 2026-08-21 at 16.03.41 (1).jpeg": {
        "title": "Share Multiple Files",
        "subtitle": "Select and send multiple files or folders at once.",
        "filename": "05_Share_Multiple_Files.png"
    },
    "WhatsApp Image 2026-08-21 at 16.01.49.jpeg": {
        "title": "Clipboard Sharing",
        "subtitle": "Seamlessly copy and paste text across devices.",
        "filename": "06_Clipboard_Sharing.png"
    },
    "WhatsApp Image 2026-08-21 at 16.03.40 (1).jpeg": {
        "title": "Manage Snippets",
        "subtitle": "Save, search, and broadcast clipboard text.",
        "filename": "07_Manage_Snippets.png"
    },
    "WhatsApp Image 2026-08-21 at 16.03.40.jpeg": {
        "title": "Clean & Intuitive",
        "subtitle": "Customize your identity and storage preferences.",
        "filename": "08_Clean_Intuitive_Interface.png"
    }
}

CANVAS_WIDTH = 1080
CANVAS_HEIGHT = 1920

# Colors for gradient background (Light Blue Theme)
BG_TOP = (240, 246, 255)      # AppColors.background
BG_BOTTOM = (126, 184, 229)   # AppColors.secondary (0xFF7EB8E5)
TEXT_COLOR = (26, 43, 61)     # AppColors.textPrimary

try:
    font_title = ImageFont.truetype("/System/Library/Fonts/Supplemental/Avenir Next.ttc", 72)
    font_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Avenir Next.ttc", 40)
    font_logo = ImageFont.truetype("/System/Library/Fonts/Supplemental/Avenir Next.ttc", 50)
except IOError:
    try:
        font_title = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 72)
        font_sub = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40)
        font_logo = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 50)
    except IOError:
        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()
        font_logo = ImageFont.load_default()

def create_gradient(width, height, color1, color2):
    base = Image.new('RGB', (width, height), color1)
    top = Image.new('RGB', (width, height), color2)
    mask = Image.new('L', (width, height))
    mask_data = []
    for y in range(height):
        mask_data.extend([int(255 * (y / height))] * width)
    mask.putdata(mask_data)
    base.paste(top, (0, 0), mask)
    return base

def add_corners(im, rad):
    circle = Image.new('L', (rad * 2, rad * 2), 0)
    draw = ImageDraw.Draw(circle)
    draw.ellipse((0, 0, rad * 2 - 1, rad * 2 - 1), fill=255)
    alpha = Image.new('L', im.size, 255)
    w, h = im.size
    alpha.paste(circle.crop((0, 0, rad, rad)), (0, 0))
    alpha.paste(circle.crop((rad, 0, rad * 2, rad)), (w - rad, 0))
    alpha.paste(circle.crop((0, rad, rad, rad * 2)), (0, h - rad))
    alpha.paste(circle.crop((rad, rad, rad * 2, rad * 2)), (w - rad, h - rad))
    im.putalpha(alpha)
    return im

def get_circular_logo(logo_path, size):
    try:
        logo = Image.open(logo_path).convert("RGBA")
        logo = logo.resize((size, size), Image.Resampling.LANCZOS)
        mask = Image.new('L', (size, size), 0)
        draw = ImageDraw.Draw(mask)
        draw.ellipse((0, 0, size, size), fill=255)
        logo.putalpha(mask)
        return logo
    except Exception as e:
        print(f"Warning: Could not load logo from {logo_path}: {e}")
        return None

logo_path = "../../../clipland/app_logo/logo.jpeg"
logo_img = get_circular_logo(logo_path, 80)

for img_path, screen_info in SCREENS.items():
    if not os.path.exists(img_path):
        print(f"File not found: {img_path}")
        continue
    
    print(f"Processing {img_path}...")
    
    title = screen_info['title']
    subtitle = screen_info['subtitle']
    filename = screen_info['filename']

    # Create canvas
    canvas = create_gradient(CANVAS_WIDTH, CANVAS_HEIGHT, BG_TOP, BG_BOTTOM)
    draw = ImageDraw.Draw(canvas)

    # 1. Draw Logo + App Name at the top left/center
    logo_text = "ClipLAN"
    logo_y = 60
    logo_text_bbox = draw.textbbox((0, 0), logo_text, font=font_logo)
    logo_text_w = logo_text_bbox[2] - logo_text_bbox[0]
    
    logo_size = 80
    spacing = 20
    total_logo_w = logo_text_w
    if logo_img:
        total_logo_w += logo_size + spacing
        
    start_x = (CANVAS_WIDTH - total_logo_w) // 2
    
    if logo_img:
        canvas.paste(logo_img, (start_x, logo_y), logo_img)
        draw.text((start_x + logo_size + spacing, logo_y + 10), logo_text, font=font_logo, fill=TEXT_COLOR)
    else:
        draw.text((start_x, logo_y + 10), logo_text, font=font_logo, fill=TEXT_COLOR)

    # 2. Draw Title
    text_y = logo_y + 120
    text_bbox = draw.textbbox((0, 0), title, font=font_title)
    text_w = text_bbox[2] - text_bbox[0]
    text_x = (CANVAS_WIDTH - text_w) // 2
    draw.text((text_x, text_y), title, font=font_title, fill=TEXT_COLOR)
    
    # 3. Draw Subtitle
    sub_y = text_y + 100
    sub_bbox = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_x = (CANVAS_WIDTH - sub_w) // 2
    draw.text((sub_x, sub_y), subtitle, font=font_sub, fill=TEXT_COLOR)

    # 4. Process screenshot
    with Image.open(img_path) as ss:
        # Calculate position for top of screenshot
        ss_y = sub_y + 120
        
        # Resize screenshot to fit gracefully inside canvas (with padding)
        available_w = CANVAS_WIDTH * 0.92
        available_h = CANVAS_HEIGHT - ss_y - 80  # 80px bottom margin
        
        ratio_w = available_w / ss.width
        ratio_h = available_h / ss.height
        ratio = min(ratio_w, ratio_h)
        
        target_w = int(ss.width * ratio)
        target_h = int(ss.height * ratio)
        ss_resized = ss.resize((target_w, target_h), Image.Resampling.LANCZOS)
        
        # Add rounded corners to screenshot
        ss_rounded = add_corners(ss_resized, 40)
        
        # Calculate horizontal center
        ss_x = (CANVAS_WIDTH - target_w) // 2
        
        # Draw shadow
        shadow = Image.new('RGBA', (CANVAS_WIDTH, CANVAS_HEIGHT), (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow)
        shadow_rect = [ss_x, ss_y, ss_x + target_w, ss_y + target_h]
        shadow_draw.rounded_rectangle(shadow_rect, radius=40, fill=(0, 0, 0, 150))
        shadow = shadow.filter(ImageFilter.GaussianBlur(30))
        canvas.paste(shadow, (0, 0), shadow)
        
        # Paste screenshot
        canvas.paste(ss_rounded, (ss_x, ss_y), ss_rounded)

    # Save
    out_path = os.path.join(OUTPUT_DIR, filename)
    canvas.save(out_path)
    print(f"Saved {out_path}")

print("All screenshots processed successfully!")
