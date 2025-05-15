import os
import re
import json
import sys
from bs4 import BeautifulSoup
from collections import defaultdict
from datetime import datetime, timedelta


if len(sys.argv) > 1:
    INPUT_HTML = sys.argv[1]
    if len(sys.argv) > 2:
        OUTPUT_DIR = sys.argv[2]
    else:
        # Default to the same directory as the input file
        OUTPUT_DIR = os.path.dirname(INPUT_HTML)

BASE_ID = 1
MAX_POSTS = 10

# Ensure output directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Print info at start
print(f"Reading HTML from: {INPUT_HTML}")
print(f"Saving JSONs to: {OUTPUT_DIR}")

# Helper functions
def clean(text):
    """Clean text by removing extra whitespace"""
    return re.sub(r'\s+', ' ', text).strip()

def create_slug(text):
    if not text:
        return ""
    # Convert to lowercase
    text = text.lower()
    # Replace non-alphanumeric characters with hyphens
    text = re.sub(r'[^a-z0-9]+', '-', text)
    # Remove leading/trailing hyphens
    text = text.strip('-')
    # Limit length
    return text[:400]

def extract_date(date_text):
    """Convert LinkedIn relative date to YYYY-MM-DD format"""
    # Get current date
    today = datetime.now()
    
    # Parse relative date formats
    if 'mo' in date_text:
        # Handle "Xmo" format (e.g., "4mo")
        months = int(re.search(r'(\d+)', date_text).group(1))
        # Calculate correct year and month
        new_month = today.month - months
        new_year = today.year
        
        # Adjust year if month becomes negative or zero
        while new_month <= 0:
            new_month += 12
            new_year -= 1
            
        date = today.replace(year=new_year, month=new_month)
    elif 'w' in date_text:
        # Handle "Xw" format
        weeks = int(re.search(r'(\d+)', date_text).group(1))
        # Use timedelta for accurate date calculation with weeks
        date = today - timedelta(weeks=weeks)
    elif 'd' in date_text:
        # Handle "Xd" format (e.g., "3d")
        days = int(re.search(r'(\d+)', date_text).group(1))
        # Use timedelta for accurate date calculation with days
        date = today - timedelta(days=days)
    elif 'y' in date_text:
        # Handle "Xy" format (e.g., "1y")
        years = int(re.search(r'(\d+)', date_text).group(1))
        date = today.replace(year=today.year - years)
    else:
        date = today
    
    # Format as YYYY-MM-DD
    return date.strftime('%Y-%m-%d')

def extract_author_info(post_container, default_name="Unknown User"):
    """Extract information about the post author"""
    author_info = {
        "name": default_name,
        "pic": "",
        "description": "",
        "slug": create_slug(default_name)
    }
    
    # For reposts, try to extract from header
    if is_repost(post_container):
        reposter_link = post_container.select_one(".update-components-header__text-view a")
        if reposter_link:
            raw_name = clean(reposter_link.get_text())
            # Clean up the name
            cleaned_name = clean_author_name(raw_name)
            author_info["name"] = cleaned_name
            author_info["slug"] = create_slug(cleaned_name)

        # Get the reposter's description
        description_elem = post_container.select_one(".update-components-header__description")
        if description_elem:
            author_info["description"] = clean(description_elem.get_text())
        
        # Find the reposter's profile image
        profile_img = post_container.select_one(".update-components-header__image img")
        if profile_img and "src" in profile_img.attrs:
            author_info["pic"] = profile_img["src"]

    else:
        # For direct posts, we need different selectors
        author_found = False
        
        # Try approach 1: Look for the actor title
        author_container = post_container.select_one(".update-components-actor__title")
        if author_container:
            author_link = author_container.select_one("a")
            if author_link:
                raw_name = clean(author_link.get_text())
                cleaned_name = clean_author_name(raw_name)
                author_info["name"] = cleaned_name
                author_info["slug"] = create_slug(cleaned_name)
                author_found = True
        
        # Try approach 2: Look for any profile links
        if not author_found:
            all_links = post_container.select("a")
            for link in all_links:
                # Check if link contains profile-like path
                href = link.get("href", "")
                if "/in/" in href and clean(link.get_text()):
                    raw_name = clean(link.get_text())
                    cleaned_name = clean_author_name(raw_name)
                    author_info["name"] = cleaned_name
                    author_info["slug"] = create_slug(cleaned_name)
                    author_found = True
                    break
        
        # Extract author description/headline
        description_elem = post_container.select_one(".update-components-actor__description")
        if description_elem:
            author_info["description"] = clean(description_elem.get_text())
            
        # If we don't find it with that selector, try alternative selectors
        if not author_info["description"]:
            alt_desc_selectors = [
                ".feed-shared-actor__description",
                ".feed-shared-actor__sub-description",
                ".update-components-actor__subtitle"
            ]
            
            for selector in alt_desc_selectors:
                desc_elem = post_container.select_one(selector)
                if desc_elem:
                    author_info["description"] = clean(desc_elem.get_text())
                    # Remove "followers" text if present
                    author_info["description"] = re.sub(r'\s*\d[\d,]*\s+followers.*$', '', author_info["description"])
                    break

        # Try to find profile image with various selectors
        pic_selectors = [
            ".update-components-actor__avatar-image",
            ".EntityPhoto-circle-0",
            ".ivm-view-attr__img--centered"
        ]
        
        for selector in pic_selectors:
            profile_img = post_container.select_one(selector)
            if profile_img and "src" in profile_img.attrs:
                author_info["pic"] = profile_img["src"]
                break
    
    return author_info

def clean_author_name(raw_name):
    """Clean author name by removing duplications and extra information"""
    # Remove degree indicators, titles, etc.
    name = re.sub(r'\s+[•]\s+.*$', '', raw_name)
    
    # Remove duplicated names
    name_parts = name.split()
    if len(name_parts) >= 2:
        half_len = len(name_parts) // 2
        if name_parts[:half_len] == name_parts[half_len:]:
            name = " ".join(name_parts[:half_len])
    
    for length in range(len(name) // 2, 0, -1):
        if name[:length] == name[length:2*length]:
            return name[:length].strip()
    
    # Remove any extra information after the name
    if '•' in name:
        name = name.split('•')[0].strip()
    
    if ' at ' in name:
        name = name.split(' at ')[0].strip()
    
    return name

def extract_original_author_info(post_container):
    """Extract information about the original post author"""
    author_container = post_container.select_one(".update-components-actor__title span[dir='ltr']")
    author_name = ""
    
    if author_container:
        # Get raw text which might contain duplicated name
        raw_name = clean(author_container.get_text())
        
        name_parts = re.split(r'•|\|', raw_name, 1)
        if len(name_parts) > 1:
            # There is a separator, take first part
            author_name = clean(name_parts[0])
        else:
            # No separator, check for duplicated name pattern
            # Pattern: Look for sequences like "CompanyNameCompanyName" or "John SmithJohn Smith"
            name_pattern = r'^(.+?)(?:\1)+$'
            match = re.match(name_pattern, raw_name)
            if match:
                # Found duplicated pattern
                author_name = match.group(1)
            else:
                # No duplicated pattern found, use as is
                author_name = raw_name
    
    # Get followers count
    followers_count = 0
    followers_span = post_container.select_one(".update-components-actor__description")
    if followers_span:
        followers_text = clean(followers_span.get_text())
        followers_match = re.search(r'(\d+,?\d*)\s*followers', followers_text)
        if followers_match:
            followers_count = int(followers_match.group(1).replace(',', ''))
    
    # Get the post date
    post_date = ""
    date_span = post_container.select_one(".update-components-actor__sub-description")
    if date_span:
        date_text = clean(date_span.get_text())
        # Extract date format like "4mo"
        date_match = re.search(r'(\d+\s*[dwmy]+o?)', date_text)
        if date_match:
            post_date = date_match.group(1)
    
    # Get author image (from the profile picture)
    author_img = post_container.select_one(".update-components-actor__avatar-image")
    pic_url = author_img.get("src") if author_img else ""
    
    # Create slug from author name
    slug = create_slug(author_name)

    post_link = ""
    link_container = post_container.select_one("a[data-control-name='view_post']")
    if link_container and 'href' in link_container.attrs:
        post_link = link_container.attrs['href']
    
    return {
        "name": author_name,
        "pic": pic_url,
        "slug": slug,
        "link": post_link
    }

def extract_post_description(post_container):
    """Extract the main content of the post"""
    description_container = post_container.select_one(".feed-shared-inline-show-more-text")
    if description_container:
        # Instead of getting the text directly, look for the full content in the span
        content_span = description_container.select_one(".update-components-text .break-words span[dir='ltr']")
        
        if content_span:
            # This gets the full content regardless of the "...more" button
            content = clean(content_span.get_text())
            
            # Now replace any "hashtag" prefix that might have been added
            content = content.replace("hashtag#", "#")
            content = content.replace("hashtaghashtag#", "#")
            
            return content
        else:
            # Fallback to the old method if we can't find the content span
            content = clean(description_container.get_text())
            content = content.replace("hashtag#", "#")
            content = content.replace("hashtaghashtag#", "#")
            
            if "…more" not in content and description_container.select_one(".feed-shared-inline-show-more-text__see-more-less-toggle"):
                content += " …more"
                
            return content
    return ""

def extract_images(post_container):
    """Extract image URLs from the post"""
    images = []
    image_containers = post_container.select(".update-components-image__image-link")
    
    for img_container in image_containers:
        img = img_container.select_one("img")
        if img and "src" in img.attrs:
            img_url = img["src"]
            # Filter to ensure we get feed images
            if "feedshare" in img_url:
                images.append(img_url)
    
    return images

def extract_engagement(post_container):
    """Extract engagement metrics (likes, comments, reposts)"""
    engagement = {"likes": 0, "comments": 0, "reposts": 0}
    
    # Extract likes
    likes_container = post_container.select_one(".social-details-social-counts__reactions-count")
    if likes_container:
        likes_text = clean(likes_container.get_text())
        try:
            # Remove any commas before converting to int
            likes_text = likes_text.replace(',', '')
            engagement["likes"] = int(likes_text)
        except ValueError:
            pass

    # Extract comments
    comments_container = post_container.select_one("li.social-details-social-counts__comments button")
    if comments_container:
        comments_text = clean(comments_container.get_text())
        match = re.search(r'(\d+)\s*comments?', comments_text)
        if match:
            engagement["comments"] = int(match.group(1))
    
    # Extract reposts - try different selectors
    reposts_container = post_container.select_one("button[aria-label*='reposts']")
    if reposts_container:
        reposts_text = clean(reposts_container.get_text())
        match = re.search(r'(\d+)\s*reposts?', reposts_text)
        if match:
            engagement["reposts"] = int(match.group(1))
    else:
        # Try alternative selector for repost counts
        reposts_alt = post_container.select_one(".social-details-social-counts__item--right-aligned:not(.social-details-social-counts__comments) button")
        if reposts_alt:
            reposts_text = clean(reposts_alt.get_text())
            match = re.search(r'(\d+)\s*reposts?', reposts_text)
            if match:
                engagement["reposts"] = int(match.group(1))
    
    return engagement

def is_repost(post_container):
    """Check if the post is a repost"""
    header_text = post_container.select_one(".update-components-header__text-view")
    return header_text and "reposted this" in header_text.get_text()

def extract_reposter_comment(post_container):
    """Extract any comment added by the reposter"""
    reposter_comment = ""
    
    comment_container = post_container.select_one(".update-components-text[dir='ltr']")
    
    text_components = post_container.select(".update-components-text")
    
    if len(text_components) > 1:
        # There's more than one text component, suggesting the first might be the reposter's comment
        reposter_comment = clean(text_components[0].get_text())
    elif comment_container:
        # If there's only one text component but it's directly under the reposter's header,
        header = post_container.select_one(".update-components-header")
        if header:
            reposter_comment = clean(comment_container.get_text())
    
    return reposter_comment

def fix_duplicated_name(name):
    """Fix duplicated names like 'BindTuningBindTuning' to 'BindTuning'"""
    if not name:
        return name
        
    # Check for exact duplications (like "BindTuningBindTuning")
    # First try: Find if the first half equals the second half
    length = len(name)
    half_length = length // 2
    
    if length % 2 == 0 and name[:half_length] == name[half_length:]:
        return name[:half_length]
    
    # Second approach: Find repeated words
    words = name.split()
    if len(words) >= 2:
        # Check for patterns like "John Smith John Smith"
        half_count = len(words) // 2
        if words[:half_count] == words[half_count:]:
            return " ".join(words[:half_count])
    
    # Third approach: Use regex to find duplicated parts
    duplicate_pattern = r'^(.+?)\1+$'
    match = re.match(duplicate_pattern, name)
    if match:
        return match.group(1)
    
    return name

def extract_posts(soup):
    """Find and extract all posts"""
    # Find all post containers
    post_containers = soup.find_all("div", class_="feed-shared-update-v2")
    return post_containers[:MAX_POSTS]  # Limit to MAX_POSTS

def generate_post_slug(description):
    """Generate a URL-friendly slug from the post description"""
    if not description:
        return ""
    
    # Take first few words
    words = description.split()[:8]
    slug_text = " ".join(words)
    
    # Create slug
    return create_slug(slug_text)

def is_video_content(post_container):
    """Check if the post contains video content"""
    # Look for video player elements
    video_player = post_container.select_one(".update-components-linkedin-video")
    if video_player:
        return True
        
    # Alternative check for video content
    video_js = post_container.select_one(".video-js")
    if video_js:
        return True
    
    # Look for specific video-related classes
    video_classes = [
        ".media-player",
        ".vjs-tech",
        ".video-s-loader"
    ]
    
    for class_name in video_classes:
        if post_container.select_one(class_name):
            return True
    
    return False

def extract_video_info(post_container):
    """Extract information about the video"""
    video_info = {"thumbnail": "", "duration": ""}
    
    # Try to get the video thumbnail
    # Look for poster image in multiple locations
    poster_elements = [
        post_container.select_one(".vjs-poster"),
        post_container.select_one(".vjs-poster-background"),
        post_container.select_one(".media-player video[poster]")
    ]
    
    for element in poster_elements:
        if element:
            if "style" in element.attrs:
                style = element["style"]
                url_match = re.search(r'url\("([^"]+)"\)', style)
                if url_match:
                    video_info["thumbnail"] = url_match.group(1)
                    break
            elif element.name == "video" and "poster" in element.attrs:
                video_info["thumbnail"] = element["poster"]
                break
    
    # Try to get video duration
    duration_elements = [
        post_container.select_one(".vjs-remaining-time-display"),
        post_container.select_one(".video-duration"),
        post_container.select_one(".media-player__duration")
    ]
    
    for element in duration_elements:
        if element:
            duration_text = clean(element.get_text())
            # Remove any minus sign
            duration_text = duration_text.replace('-', '').strip()
            if duration_text:
                video_info["duration"] = duration_text
                break
    
    return video_info

def is_document_carousel(post_container):
    """Check if the post contains a document carousel"""
    # Check for the document-s-container class
    if post_container.select_one(".document-s-container"):
        return True
    
    # Check for the document container with specific class
    if post_container.select_one(".update-components-document__container"):
        return True
    
    # Check for document iframe
    iframe = post_container.select_one("iframe[title*='Document player']")
    if iframe:
        return True
    
    return False

def extract_document_info(post_container):
    """Extract information about the document carousel"""
    document_info = {
        "type": "carousel",
        "title": ""
    }
    
    # Extract title from iframe
    iframe = post_container.select_one("iframe[title*='Document player']")
    if iframe and "title" in iframe.attrs:
        title = iframe["title"]
        # Clean up title if it has a prefix
        if "Document player for:" in title:
            title = title.replace("Document player for:", "").strip()
        elif "Document player for" in title:
            title = title.replace("Document player for", "").strip()
        document_info["title"] = title
    
    # If no title from iframe, try other elements
    if not document_info["title"]:
        title_elem = post_container.select_one(".document-s-container__title, .update-components-document__title")
        if title_elem:
            document_info["title"] = clean(title_elem.get_text())
    
    return document_info

# Create a function that handles media detection for all post types
def extract_media_info(post_container):
    """Extract media information from any post type"""
    media = {}
    
    if is_video_content(post_container):
        video_info = extract_video_info(post_container)
        media = {
            "type": "video",
            "thumbnail": video_info.get("thumbnail", ""),
            "duration": video_info.get("duration", "")
        }
    elif is_document_carousel(post_container):
        document_info = extract_document_info(post_container)
        media = {
            "type": document_info["type"],
            "title": document_info.get("title", ""),
            "info": "Images not visible in the HTML" 
        }
    elif extract_images(post_container):
        media = {
            "type": "image",
            "urls": extract_images(post_container)
        }
    else:
        media = {
            "type": "none"
        }
    
    return media

# Main processing function
def process_posts(soup):
    posts = extract_posts(soup)
    results = []
    
    for i, post_container in enumerate(posts):
        repost = is_repost(post_container)
        
        # Common operations for both post types
        post_content = extract_post_description(post_container)
        author_info = extract_author_info(post_container)
        engagement = extract_engagement(post_container)
        
        # Get post date
        date_span = post_container.select_one(".update-components-actor__sub-description")
        rel_date = ""
        if date_span:
            date_text = clean(date_span.get_text())
            date_match = re.search(r'(\d+\s*[dwmy]+o?)', date_text)
            if date_match:
                rel_date = date_match.group(1)
        
        formatted_date = extract_date(rel_date)
        
        # Generate slug from content
        post_slug = generate_post_slug(post_content)
        
        # Extract media - use the same function for both post types
        media = extract_media_info(post_container)
        
        if repost:
            # Process as repost
            original_author = extract_original_author_info(post_container)
            if original_author["name"]:
                original_author["name"] = fix_duplicated_name(original_author["name"])
            
            content_slug = generate_post_slug(post_content)
            
            # Check for reposter comment
            reposter_comment = extract_reposter_comment(post_container)
            has_reposter_comment = bool(reposter_comment)
            
            post = {
                "id": BASE_ID + i,
                "post_type": "repost",
                "date": formatted_date,
                "author": author_info,  # The reposter
                "social_engagement": {
                    "likes": engagement["likes"],
                    "comments": engagement["comments"],
                    "reposts": engagement["reposts"]
                },
                "original_post": {
                    "author": original_author,
                    "content": post_content,
                    "slug": content_slug,
                    "media": media
                }
            }
            
            if has_reposter_comment:
                post["reposter_comment"] = reposter_comment
                
        else:
            # Regular post
            post = {
                "id": BASE_ID + i,
                "post_type": "post",
                "date": formatted_date,
                "content": post_content,
                "slug": post_slug,
                "media": media,
                "author": author_info,
                "social_engagement": {  
                    "likes": engagement["likes"],
                    "comments": engagement["comments"],
                    "reposts": engagement["reposts"]
                }
            }
        
        results.append(post)
    
    return results


# Load HTML and process
try:
    with open(INPUT_HTML, "r", encoding="utf-8") as file:
        soup = BeautifulSoup(file, "html.parser")
    
    # Process HTML and save results
    posts = process_posts(soup)
    
    for post in posts:
        output_file = os.path.join(OUTPUT_DIR, f"Post_{post['id']}.json")
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(post, f, indent=2, ensure_ascii=False)
    
    print(f"DONE: {len(posts)} JSONs saved in '{OUTPUT_DIR}/'")
    sys.exit(0)
    
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)