import cv2
import pytesseract
from PIL import Image, ImageDraw, ImageFont
import os
import shutil

TARGETS = [
    "WhatsApp Image 2026-08-21 at 16.01.46.jpeg",
    "WhatsApp Image 2026-08-21 at 16.03.41.jpeg",
    "WhatsApp Image 2026-08-21 at 16.01.47.jpeg",
    "WhatsApp Image 2026-08-21 at 16.01.49.jpeg"
]

def patch_image(image_path):
    if not os.path.exists(image_path):
        print(f"File not found: {image_path}")
        return

    # Backup original
    backup_path = image_path + ".bak"
    if not os.path.exists(backup_path):
        shutil.copy(image_path, backup_path)

    # Read image using cv2
    img = cv2.imread(image_path)
    if img is None:
        print(f"Could not read {image_path}")
        return
        
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    
    # Use tesseract to find data
    data = pytesseract.image_to_data(gray, output_type=pytesseract.Output.DICT)
    
    found = False
    for i in range(len(data['text'])):
        text = data['text'][i].strip()
        if "clipland" in text.lower():
            x = data['left'][i]
            y = data['top'][i]
            w = data['width'][i]
            h = data['height'][i]
            
            # Expand the bounding box slightly to cover the word fully
            x -= 5
            y -= 5
            w += 10
            h += 10
            
            # Ensure it doesn't go out of bounds
            x = max(0, x)
            y = max(0, y)
            
            # Sample background color (just above the box)
            sample_y = max(0, y - 5)
            sample_x = x + w // 2
            bg_color_bgr = img[sample_y, sample_x]
            bg_color = (int(bg_color_bgr[2]), int(bg_color_bgr[1]), int(bg_color_bgr[0])) # BGR to RGB
            
            # Use PIL to draw the patch and text
            pil_img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
            draw = ImageDraw.Draw(pil_img)
            
            # Draw rectangle
            draw.rectangle([x, y, x+w, y+h], fill=bg_color)
            
            # Draw text
            try:
                # Try a nice font
                font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", int(h*0.8))
            except:
                font = ImageFont.load_default()
                
            # We want to match text color, let's assume it's white or black. Since it's a UI, probably white.
            # We can sample a pixel from the original text (center of the bounding box)
            center_x = x + w // 2
            center_y = y + h // 2
            text_color_bgr = img[center_y, center_x]
            text_color = (int(text_color_bgr[2]), int(text_color_bgr[1]), int(text_color_bgr[0]))
            
            # if the text was white it will be close to 255,255,255
            # Sometimes sampling hits an edge, let's just use White if bg is dark, Black if bg is light
            brightness = sum(bg_color) / 3
            final_text_color = (255, 255, 255) if brightness < 128 else (0, 0, 0)
            
            # Center the new text in the box
            # PIL textbbox
            bbox = draw.textbbox((0, 0), "ClipLAN", font=font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            tx = x + (w - tw) // 2
            ty = y + (h - th) // 2
            
            draw.text((tx, ty), "ClipLAN", fill=final_text_color, font=font)
            
            # Save the patched image
            pil_img.save(image_path)
            print(f"Successfully patched {image_path} at ({x},{y},{w},{h})")
            found = True
            break
            
    if not found:
        print(f"Could not find 'Clipland' in {image_path} via OCR.")

if __name__ == "__main__":
    for target in TARGETS:
        patch_image(target)
