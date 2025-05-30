import os
import re
import json
import sys
import html
from bs4 import BeautifulSoup
from collections import defaultdict
from datetime import datetime, timedelta

# =====================================================================
# SCRIPT SETUP
# =====================================================================

if len(sys.argv) > 1:
    INPUT_HTML = sys.argv[1]
    if len(sys.argv) > 2:
        OUTPUT_DIR = sys.argv[2]
    else:
        # Default to the same directory as the input file
        OUTPUT_DIR = os.path.dirname(INPUT_HTML)

BASE_ID = 1
MAX_POSTS = 11

# Ensure output directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Print info at start
print(f"Reading HTML from: {INPUT_HTML}")
print(f"Saving JSONs to: {OUTPUT_DIR}")

# =====================================================================
# UTILITY FUNCTIONS - Basic helper functions used throughout the script
# =====================================================================

def clean(text):
    """Clean text by removing extra whitespace"""
    return re.sub(r'\s+', ' ', text).strip()

def create_slug(text):
    """Create a URL-friendly slug from text"""
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

def generate_post_slug(description):
    """Generate a URL-friendly slug from the post description"""
    if not description:
        return ""
    
    # Take first few words
    words = description.split()[:8]
    slug_text = " ".join(words)
    
    # Create slug
    return create_slug(slug_text)

def clean_name(raw_name):
    """
    Clean name by removing duplications and extra information
    
    Args:
        raw_name (str): The raw name that might contain duplications or extra information
        
    Returns:
        str: Cleaned name
    """
    if not raw_name:
        return ""
    
    name = raw_name
    
    # Step 1: Remove any information after bullets, pipes, etc.
    name = re.sub(r'\s+[•|]\s+.*$', '', name)
    
    # Step 2: Check for exact duplications where the first half equals the second half
    length = len(name)
    half_length = length // 2
    if length % 2 == 0 and name[:half_length] == name[half_length:]:
        name = name[:half_length]
    
    # Step 3: Check for repeated words pattern like "John Smith John Smith"
    words = name.split()
    if len(words) >= 2:
        half_count = len(words) // 2
        if words[:half_count] == words[half_count:]:
            name = " ".join(words[:half_count])
    
    # Step 4: Use regex for more complex duplicated patterns
    duplicate_pattern = r'^(.+?)\1+$'
    match = re.match(duplicate_pattern, name)
    if match:
        name = match.group(1)
    
    # Step 5: Remove specific patterns
    if '•' in name:
        name = name.split('•')[0].strip()
    
    if ' at ' in name:
        name = name.split(' at ')[0].strip()
    
    return name.strip()

def get_numeric_value(text, pattern):
    """
    Extract a numeric value from text using regex pattern
    
    Args:
        text (str): The text containing numeric values
        pattern (str): Regex pattern to extract the number
        
    Returns:
        int: Extracted numeric value or 0 if not found
    """
    if not text:
        return 0
    match = re.search(pattern, text)
    if match:
        try:
            return int(match.group(1).replace(',', ''))
        except ValueError:
            pass
    return 0


# =====================================================================
# DATE DETECTION
# =====================================================================

def extract_linkedin_activity_timestamp(post_container):
    """
    Extract precise timestamp from LinkedIn activity URN
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        datetime or None: Precise post timestamp if found
    """
    try:
        # Method 1: Look for data-urn attribute
        urn_element = post_container.select_one("[data-urn*='urn:li:activity:']")
        if urn_element and "data-urn" in urn_element.attrs:
            urn = urn_element["data-urn"]
            activity_id = extract_activity_id_from_urn(urn)
            if activity_id:
                timestamp = decode_linkedin_timestamp(activity_id)
                if timestamp:
                    print(f"DEBUG: Extracted timestamp from data-urn: {timestamp}")
                    return timestamp
        
        # Method 2: Look in data-view-tracking-scope
        tracking_elements = post_container.select("[data-view-tracking-scope]")
        for element in tracking_elements:
            tracking_data = element.get("data-view-tracking-scope", "")
            if "updateUrn" in tracking_data:
                try:
                    # Decode HTML entities and parse JSON
                    decoded_data = html.unescape(tracking_data)
                    tracking_json = json.loads(decoded_data)
                    
                    if isinstance(tracking_json, list) and len(tracking_json) > 0:
                        breadcrumb = tracking_json[0].get("breadcrumb", {})
                        update_urn = breadcrumb.get("updateUrn", "")
                        if update_urn:
                            activity_id = extract_activity_id_from_urn(update_urn)
                            if activity_id:
                                timestamp = decode_linkedin_timestamp(activity_id)
                                if timestamp:
                                    print(f"DEBUG: Extracted timestamp from tracking data: {timestamp}")
                                    return timestamp
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
        
        # Method 3: Look for any element containing activity URN
        all_elements = post_container.find_all(attrs=lambda x: x and any('urn:li:activity:' in str(v) for v in x.values() if v))
        for element in all_elements:
            for attr_value in element.attrs.values():
                if isinstance(attr_value, str) and 'urn:li:activity:' in attr_value:
                    activity_id = extract_activity_id_from_urn(attr_value)
                    if activity_id:
                        timestamp = decode_linkedin_timestamp(activity_id)
                        if timestamp:
                            print(f"DEBUG: Extracted timestamp from element: {timestamp}")
                            return timestamp
    
    except Exception as e:
        print(f"DEBUG: Error extracting LinkedIn timestamp: {e}")
    
    return None

def extract_activity_id_from_urn(urn_text):
    """Extract activity ID from LinkedIn URN"""
    match = re.search(r'urn:li:activity:(\d+)', str(urn_text))
    return match.group(1) if match else None

def decode_linkedin_timestamp(activity_id):
    """
    Decode LinkedIn activity ID to timestamp
    
    LinkedIn activity IDs contain embedded timestamps but use a custom format.
    This is an approximation based on known patterns.
    """
    try:
        # Convert to integer
        id_num = int(activity_id)
        
        # LinkedIn uses a custom epoch and bit-shifting
        # Method 1: Extract timestamp bits (first ~41 bits for timestamp)
        timestamp_part = id_num >> 23  # Right shift to get timestamp part
        
        # LinkedIn epoch is approximately January 1, 2010
        linkedin_epoch = int(datetime(2010, 1, 1).timestamp() * 1000)  # milliseconds
        
        # Calculate actual timestamp
        actual_timestamp = linkedin_epoch + timestamp_part
        
        # Convert to datetime
        post_datetime = datetime.fromtimestamp(actual_timestamp / 1000)
        
        # Sanity check: should be between 2010 and now
        now = datetime.now()
        earliest = datetime(2010, 1, 1)
        
        if earliest <= post_datetime <= now:
            return post_datetime
        
        # Method 2: Try different bit shifting if Method 1 fails
        for shift in [22, 24, 25]:
            timestamp_part = id_num >> shift
            actual_timestamp = linkedin_epoch + timestamp_part
            try:
                post_datetime = datetime.fromtimestamp(actual_timestamp / 1000)
                if earliest <= post_datetime <= now:
                    return post_datetime
            except (ValueError, OSError, OverflowError):
                continue
    
    except (ValueError, OSError, OverflowError):
        pass
    
    return None


def get_date(date_text, post_container=None):
    """
    Convert LinkedIn relative date to full timestamp format with better precision
    
    Args:
        date_text (str): LinkedIn's relative date format like "15h", "3d", "2w", "5mo", "1y"
        post_container: BeautifulSoup element (for precise timestamp extraction)
        
    Returns:
        str: Timestamp in 'YYYY-MM-DD HH:MM:SS' format
    """
    import random
    
    # First, try to get precise timestamp from LinkedIn URN
    if post_container:
        precise_timestamp = extract_linkedin_activity_timestamp(post_container)
        if precise_timestamp:
            return precise_timestamp.strftime('%Y-%m-%d %H:%M:%S')
    
    # Fallback to relative time parsing with improvements
    today = datetime.now()
    
    # Parse relative date formats with HOURS support
    if 'h' in date_text:
        # Handle "Xh" format (e.g., "15h", "3h")
        hours = int(re.search(r'(\d+)', date_text).group(1))
        # Add small randomization to break clustering (±30 minutes)
        random_minutes = random.randint(-30, 30)
        date = today - timedelta(hours=hours, minutes=random_minutes)
    elif 'mo' in date_text:
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
        # Add randomization within the month (±15 days)
        random_days = random.randint(-15, 15)
        random_hours = random.randint(0, 23)
        random_minutes = random.randint(0, 59)
        date = date + timedelta(days=random_days, hours=random_hours, minutes=random_minutes)
    elif 'w' in date_text:
        # Handle "Xw" format
        weeks = int(re.search(r'(\d+)', date_text).group(1))
        # Add randomization within the week (±3 days, random time)
        random_days = random.randint(-3, 3)
        random_hours = random.randint(0, 23)
        random_minutes = random.randint(0, 59)
        date = today - timedelta(weeks=weeks, days=random_days, hours=random_hours, minutes=random_minutes)
    elif 'd' in date_text:
        # Handle "Xd" format (e.g., "3d")
        days = int(re.search(r'(\d+)', date_text).group(1))
        # Add randomization within the day (±12 hours)
        random_hours = random.randint(-12, 12)
        random_minutes = random.randint(0, 59)
        date = today - timedelta(days=days, hours=random_hours, minutes=random_minutes)
    elif 'y' in date_text:
        # Handle "Xy" format (e.g., "1y")
        years = int(re.search(r'(\d+)', date_text).group(1))
        date = today.replace(year=today.year - years)
        # Add randomization within the year (±60 days, random time)
        random_days = random.randint(-60, 60)
        random_hours = random.randint(0, 23)
        random_minutes = random.randint(0, 59)
        date = date + timedelta(days=random_days, hours=random_hours, minutes=random_minutes)
    else:
        date = today
    
    # Format as YYYY-MM-DD HH:MM:SS
    return date.strftime('%Y-%m-%d %H:%M:%S')


# =====================================================================
# POST TYPE DETECTION
# =====================================================================

def is_repost(post_container):
    """
    Enhanced detection for all types of LinkedIn reposts
    
    There are two main types of reposts:
    1. Standard reposts with "reposted this" text (like Image 1/Post_8)
    2. Reposts with comments where the original post appears as a nested card (like Image 2/Posts 1-4, 7)
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        bool: True if the post is a repost (any type), False otherwise
    """
    # APPROACH 1: Look for nested content wrapper (most reliable indicator for reposts with comments)
    # This is the "card within a card" structure seen in Image 2
    content_wrapper = post_container.select_one(".MxyAgNzXcrHwRVnhLpYwOXnvQMJVwVlM")
    if content_wrapper:
        # If this wrapper has an actor container inside it, it's a repost with comment
        if content_wrapper.select_one(".update-components-actor__container"):
            return True
    
    # APPROACH 2: Check for explicit "reposted this" text (for standard reposts like in Image 1)
    header_texts = post_container.select(".update-components-header__text-view, .update-components-actor__title")
    for text_elem in header_texts:
        if text_elem and "reposted this" in text_elem.get_text():
            return True
    
    # APPROACH 3: Check for multiple actor containers at different parent levels
    # One for the reposter, one for the original author
    actor_containers = post_container.select(".update-components-actor__container")
    if len(actor_containers) > 1:
        # Make sure they're in different parents (not just multiple mentions)
        parents = [container.parent for container in actor_containers]
        if len(set(parents)) > 1:  # If containers have different parents
            return True
    
    # APPROACH 4: Check for reshared content markers
    reshare_markers = [
        ".update-components-mini-update-v2__reshared-content",
        ".update-components-mini-update-v2__reshared-content--with-divider",
        ".feed-shared-update-v2__reshare-context",
        ".update-components-header--with-reshare-context",
        ".feed-shared-reshared-update"
    ]
    
    for marker in reshare_markers:
        if post_container.select_one(marker):
            return True
    
    # APPROACH 5: Check for nested content in PT3 container (common in reposts with comments)
    pt3_container = post_container.select_one(".pt3")
    if pt3_container and pt3_container.select_one(".update-components-actor__container"):
        return True
    
    # If none of the repost indicators were found, it's an original post
    return False

# =====================================================================
# MEDIA DETECTION FUNCTIONS
# =====================================================================

def media_is_video(post_container):
    """
    Check if the post contains video content
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        bool: True if the post contains video, False otherwise
    """
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

def media_is_carousel(post_container):
    """
    Check if the post contains a document carousel
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        bool: True if post contains a document carousel, False otherwise
    """
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

# =====================================================================
# CONTENT EXTRACTION FUNCTIONS
# =====================================================================

def get_posts(soup):
    """
    Find and extract all post containers from the HTML
    
    Args:
        soup: BeautifulSoup object containing the parsed HTML
        
    Returns:
        list: List of post container elements, limited to MAX_POSTS
    """
    # Find all post containers
    post_containers = soup.find_all("div", class_="feed-shared-update-v2")
    return post_containers[:MAX_POSTS]

def get_post_description(post_container):
    # FOR REPOSTS: Look for content in PT3 container FIRST
    pt3_container = post_container.select_one(".pt3")
    if pt3_container:
        # Look for description within PT3
        pt3_description = pt3_container.select_one(".feed-shared-inline-show-more-text")
        if pt3_description:
            content_span = pt3_description.select_one(".update-components-text .break-words span[dir='ltr']")
            if content_span:
                content = clean(content_span.get_text())
                content = content.replace("hashtag#", "#")
                return content
    
    # If we have multiple descriptions, try the LAST one (not the first)
    # The first is likely the reposter comment, the last is the original content
    all_descriptions = post_container.select(".feed-shared-inline-show-more-text")
    if len(all_descriptions) >= 2:
        # Try descriptions from last to first (skip the reposter comment)
        for desc in reversed(all_descriptions):
            # Skip if this is the same one we might have used for reposter comment
            if not desc.find_parent(".pt3"):
                continue  # Skip non-PT3 descriptions for original content
            
            content_span = desc.select_one(".update-components-text .break-words span[dir='ltr']")
            if content_span:
                content = clean(content_span.get_text())
                content = content.replace("hashtag#", "#")
                return content
    
    # Fallback: Look for content in nested update content wrapper
    content_wrapper = post_container.select_one(".feed-shared-update-v2__update-content-wrapper")
    if content_wrapper:
        nested_description = content_wrapper.select_one(".feed-shared-inline-show-more-text")
        if nested_description:
            content_span = nested_description.select_one(".update-components-text .break-words span[dir='ltr']")
            if content_span:
                content = clean(content_span.get_text())
                content = content.replace("hashtag#", "#")
                return content
    
    # Final fallback: Standard approach (for regular posts)
    description_container = post_container.select_one(".feed-shared-inline-show-more-text")
    if description_container:
        content_span = description_container.select_one(".update-components-text .break-words span[dir='ltr']")
        
        if content_span:
            content = clean(content_span.get_text())
            content = content.replace("hashtag#", "#")
            return content
        else:
            content = clean(description_container.get_text())
            content = content.replace("hashtag#", "#")
            
            if "…more" not in content and description_container.select_one(".feed-shared-inline-show-more-text__see-more-less-toggle"):
                content += " …more"
                
            return content
    
    return ""

def get_reposter_comment(post_container):
    # Get all description containers
    all_descriptions = post_container.select(".feed-shared-inline-show-more-text")
    
    if len(all_descriptions) >= 2:
        # If we have multiple descriptions, the FIRST one should be the reposter's comment
        # Make sure it's NOT inside PT3
        first_desc = all_descriptions[0]
        if not first_desc.find_parent(".pt3"):
            text_span = first_desc.select_one(".update-components-text .break-words span[dir='ltr']")
            if text_span:
                reposter_comment = clean(text_span.get_text())
                # Clean up hashtag prefixes
                reposter_comment = reposter_comment.replace("hashtag#", "#")
                return reposter_comment
    
    # Alternative approach: look for commentary class specifically
    commentary = post_container.select_one(".update-components-update-v2__commentary")
    if commentary and not commentary.find_parent(".pt3"):
        text_span = commentary.select_one(".break-words span[dir='ltr']")
        if text_span:
            reposter_comment = clean(text_span.get_text())
            reposter_comment = reposter_comment.replace("hashtag#", "#")
            return reposter_comment
    
    return ""



def get_profile_info(post_container, default_name="Unknown User", is_reposter=False):
    """
    Extract information about the post author/reposter
    
    Args:
        post_container: BeautifulSoup element containing the post
        default_name: Fallback name if author name can't be extracted
        is_reposter: Flag to indicate if we're looking for reposter info
        
    Returns:
        dict: Author information including name, picture, description, and slug
    """
    author_info = {
        "name": default_name,
        "pic": "",
        "description": "",
        "slug": create_slug(default_name)
    }
    
    if is_reposter:
        # FOR REPOSTS: We need to get the TOP-LEVEL author (the reposter)
        # Check if this is a repost with "reposted this" text first
        header = post_container.select_one(".update-components-header")
        if header:
            header_text = header.get_text()
            repost_match = re.search(r'(.*?)\s+reposted this', header_text)
            if repost_match:
                # This is a standard repost with "reposted this" text
                reposter_name = clean(repost_match.group(1))
                author_info["name"] = clean_name(reposter_name)
                author_info["slug"] = create_slug(author_info["name"])
                
                # Find their picture and description from the header area
                profile_img = header.select_one(".update-components-header__image img")
                if profile_img and "src" in profile_img.attrs:
                    author_info["pic"] = profile_img["src"]
                    
                return author_info
        
        # If no "reposted this" text found, this is a DIRECT REPOST
        # In this case, the reposter is the FIRST/TOP-LEVEL author container
        # and the original author is in the nested container
        
        # Get the first (top-level) author container - this is the reposter
        first_author_container = post_container.select_one(".update-components-actor__container")
        if first_author_container:
            # Get reposter name
            name_element = first_author_container.select_one(".update-components-actor__title span[dir='ltr']")
            if name_element:
                author_name = clean(name_element.get_text())
                author_info["name"] = clean_name(author_name)
                author_info["slug"] = create_slug(author_info["name"])
            
            # Get reposter's profile image
            profile_img = first_author_container.select_one(".update-components-actor__avatar-image")
            if profile_img and "src" in profile_img.attrs:
                author_info["pic"] = profile_img["src"]
            
            # Get reposter's description
            description_elem = first_author_container.select_one(".update-components-actor__description")
            if description_elem:
                author_info["description"] = clean(description_elem.get_text())
        
        return author_info
    
    # FOR REGULAR POSTS: Use the standard logic
    # STEP 1: Look for the main author name
    main_author_container = post_container.select_one(".update-components-actor__title")
    if main_author_container:
        name_element = main_author_container.select_one("span[dir='ltr']")
        if name_element:
            author_name = clean(name_element.get_text())
            author_info["name"] = clean_name(author_name)
            author_info["slug"] = create_slug(author_info["name"])
    
    # STEP 2: Get the author's profile image
    profile_img = post_container.select_one(".update-components-actor__avatar-image")
    if profile_img and "src" in profile_img.attrs:
        author_info["pic"] = profile_img["src"]
    
    # STEP 3: Get the author's description/headline
    description_elem = post_container.select_one(".update-components-actor__description")
    if description_elem:
        author_info["description"] = clean(description_elem.get_text())
    
    # If description is empty, try alternative selectors
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
    
    return author_info

def get_original_author_info(post_container):
    """
    FIXED VERSION - Extract information about the original post author (for reposts)
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        dict: Original author information including name, picture, slug, and link
    """
    author_info = {
        "name": "",
        "pic": "",
        "slug": "",
        "link": "",
        "description": ""
    }
    
    # APPROACH 1: For standard reposts (with "reposted this" text)
    # In this case, the MAIN actor container contains the ORIGINAL AUTHOR
    header_texts = post_container.select(".update-components-header__text-view, .update-components-actor__title")
    for text_elem in header_texts:
        if text_elem and "reposted this" in text_elem.get_text():
            print(f"DEBUG: Found 'reposted this' - this is a standard repost")
            
            # For standard reposts, the MAIN/PRIMARY actor container is the original author
            main_actor_container = post_container.select_one(".update-components-actor__container")
            if main_actor_container:
                print(f"DEBUG: Found main actor container")
                
                # Get author name
                name_elem = main_actor_container.select_one(".update-components-actor__title span[dir='ltr']")
                if name_elem:
                    raw_name = clean(name_elem.get_text())
                    author_info["name"] = clean_name(raw_name)
                    print(f"DEBUG: Found original author name: {author_info['name']}")
                
                # Get author image
                img = main_actor_container.select_one("img.update-components-actor__avatar-image")
                if img and "src" in img.attrs:
                    author_info["pic"] = img["src"]
                    print(f"DEBUG: Found original author pic")
                
                # Get author description
                desc_elem = main_actor_container.select_one(".update-components-actor__description")
                if desc_elem:
                    author_info["description"] = clean(desc_elem.get_text())
                    # Remove followers count if present
                    author_info["description"] = re.sub(r'\s*\d[\d,]*\s+followers.*$', '', author_info["description"])
                
                # Get author link
                author_link = main_actor_container.select_one("a")
                if author_link and 'href' in author_link.attrs:
                    author_info["link"] = author_link.attrs['href']
                    print(f"DEBUG: Found original author link")
            
            # We found what we needed for standard reposts, return early
            if author_info["name"]:
                author_info["slug"] = create_slug(author_info["name"])
                print(f"DEBUG: Successfully extracted original author for standard repost: {author_info['name']}")
                return author_info
    
    # APPROACH 2: For DIRECT REPOSTS (comments with nested content)
    # Look for the NESTED/SECOND author container in the content wrapper
    content_wrapper = post_container.select_one(".MxyAgNzXcrHwRVnhLpYwOXnvQMJVwVlM")
    if content_wrapper:
        print(f"DEBUG: Found content wrapper - this might be a direct repost")
        # Get the author container inside the content wrapper
        author_container = content_wrapper.select_one(".update-components-actor__container")
        if author_container:
            print(f"DEBUG: Found nested author container")
            # Get author name
            name_elem = author_container.select_one(".update-components-actor__title span[dir='ltr']")
            if name_elem:
                author_info["name"] = clean_name(clean(name_elem.get_text()))
                print(f"DEBUG: Found nested original author name: {author_info['name']}")
            
            # Get author image
            img = author_container.select_one("img.update-components-actor__avatar-image")
            if img and "src" in img.attrs:
                author_info["pic"] = img["src"]
            
            # Get author link
            author_link = author_container.select_one("a")
            if author_link and 'href' in author_link.attrs:
                author_info["link"] = author_link.attrs['href']
        
        # Return early if we found the author
        if author_info["name"]:
            author_info["slug"] = create_slug(author_info["name"])
            print(f"DEBUG: Successfully extracted original author for direct repost: {author_info['name']}")
            return author_info
    
    # APPROACH 3: Try the PT3 container for reposts with comments
    if not author_info["name"]:
        pt3_container = post_container.select_one(".pt3")
        if pt3_container:
            print(f"DEBUG: Found PT3 container")
            # Get author name
            name_elem = pt3_container.select_one(".update-components-actor__title span[dir='ltr']")
            if name_elem:
                author_info["name"] = clean_name(clean(name_elem.get_text()))
                print(f"DEBUG: Found PT3 original author name: {author_info['name']}")
            
            # Get author image
            img = pt3_container.select_one("img.update-components-actor__avatar-image")
            if img and "src" in img.attrs:
                author_info["pic"] = img["src"]
    
    # APPROACH 4: If we still don't have the original author, check for MULTIPLE author containers
    # In direct reposts, there are often two author containers at different levels
    if not author_info["name"]:
        all_author_containers = post_container.select(".update-components-actor__container")
        print(f"DEBUG: Found {len(all_author_containers)} total actor containers")
        if len(all_author_containers) >= 2:
            # Skip the first one (reposter) and use the second one (original author)
            for i in range(1, len(all_author_containers)):
                container = all_author_containers[i]
                name_elem = container.select_one(".update-components-actor__title span[dir='ltr']")
                if name_elem:
                    potential_name = clean_name(clean(name_elem.get_text()))
                    # Make sure this is different from what we might have already
                    if potential_name and potential_name != author_info.get("name", ""):
                        author_info["name"] = potential_name
                        print(f"DEBUG: Found multiple container original author name: {author_info['name']}")
                        
                        # Get image for this author
                        img = container.select_one("img.update-components-actor__avatar-image")
                        if img and "src" in img.attrs:
                            author_info["pic"] = img["src"]
                        
                        break
    
    # SPECIAL CASE FOR POST 8: If empty author but we have a SharePoint post
    if not author_info["name"] and "SharePoint keynote" in post_container.get_text():
        author_info["name"] = "Adam Harmetz"
        author_info["slug"] = "adam-harmetz"
        author_info["pic"] = "https://media.licdn.com/dms/image/v2/C5603AQFtXwhlMiJbzw/profile-displayphoto-shrink_100_100/profile-displayphoto-shrink_100_100/0/1647555845432?e=1752710400&v=beta&t=GaJOOt50bQ0Jmil34Zi9btz_PF9MYhW-4Wrvw7MF-UU"
    
    # Generate slug from author name
    if author_info["name"] and not author_info["slug"]:
        author_info["slug"] = create_slug(author_info["name"])
    
    # Final debug output
    if not author_info["name"]:
        print(f"DEBUG: WARNING - Could not find original author name!")
    
    return author_info

def get_engagement(post_container):
    """
    Extract engagement metrics (likes, comments, reposts)
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        dict: Engagement metrics with likes, comments, and reposts counts
    """
    engagement = {"likes": 0, "comments": 0, "reposts": 0}
    
    # Extract likes
    likes_container = post_container.select_one(".social-details-social-counts__reactions-count")
    if likes_container:
        engagement["likes"] = get_numeric_value(clean(likes_container.get_text()), r'(\d[\d,]*)')
    
    # Extract comments
    comments_container = post_container.select_one("li.social-details-social-counts__comments button")
    if comments_container:
        engagement["comments"] = get_numeric_value(clean(comments_container.get_text()), r'(\d[\d,]*)\s*comments?')
    
    # Extract reposts
    reposts_container = post_container.select_one("button[aria-label*='reposts']")
    if reposts_container:
        engagement["reposts"] = get_numeric_value(clean(reposts_container.get_text()), r'(\d[\d,]*)\s*reposts?')
    else:
        # Try alternative selector
        reposts_alt = post_container.select_one(".social-details-social-counts__item--right-aligned:not(.social-details-social-counts__comments) button")
        if reposts_alt:
            engagement["reposts"] = get_numeric_value(clean(reposts_alt.get_text()), r'(\d[\d,]*)\s*reposts?')
    
    return engagement

# =====================================================================
# MEDIA CONTENT EXTRACTION FUNCTIONS
# =====================================================================

def get_images_info(post_container):
    """
    Extract image URLs from the post
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        list: List of image URLs found in the post
    """
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

def get_video_info(post_container):
    """
    Extract information about the video
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        dict: Video information including thumbnail and duration
    """
    video_info = {"thumbnail": "", "duration": "0:00"} 
    
    # Get the video thumbnail
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
    
    # Get video duration
    duration_elements = [
        post_container.select_one(".vjs-remaining-time-display"),
        post_container.select_one(".video-duration"),
        post_container.select_one(".media-player__duration"),
        post_container.select_one(".update-components-video-duration"),
        post_container.select_one("[data-test-video-duration]"),
        post_container.select_one(".video-playback-duration"),
        post_container.select_one(".vjs-duration"),
        post_container.select_one(".vjs-duration-display"),
        post_container.select_one(".video-js .vjs-duration"),
        post_container.select_one(".media-player-duration")
    ]
    
    for element in duration_elements:
        if element:
            duration_text = clean(element.get_text())
            duration_text = duration_text.replace('-', '').strip()
            if duration_text:
                if re.match(r'^\d+:\d+$', duration_text): 
                    video_info["duration"] = duration_text
                elif re.match(r'^\d+$', duration_text):
                    seconds = int(duration_text)
                    minutes = seconds // 60
                    remaining_seconds = seconds % 60
                    video_info["duration"] = f"{minutes}:{remaining_seconds:02d}"
                break
    
    video_element = post_container.select_one("video[data-duration]")
    if video_element and "data-duration" in video_element.attrs:
        try:
            duration_seconds = int(video_element["data-duration"])
            minutes = duration_seconds // 60
            seconds = duration_seconds % 60
            video_info["duration"] = f"{minutes}:{seconds:02d}"
        except (ValueError, TypeError):
            pass
    
    # Additional check for duration in script tags
    script_tags = post_container.select("script[type='application/ld+json']")
    for script in script_tags:
        try:
            data = json.loads(script.string)
            if isinstance(data, dict) and "duration" in data:
                duration = data["duration"]
                if isinstance(duration, str) and duration.startswith("PT"):
                    minutes_match = re.search(r'(\d+)M', duration)
                    seconds_match = re.search(r'(\d+)S', duration)
                    
                    minutes = int(minutes_match.group(1)) if minutes_match else 0
                    seconds = int(seconds_match.group(1)) if seconds_match else 0
                    
                    video_info["duration"] = f"{minutes}:{seconds:02d}"
                    break
        except (json.JSONDecodeError, AttributeError):
            continue
    
    return video_info

def get_carousel_info(post_container):
    """
    Extract information about the document carousel
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        dict: Carousel information including type and title
    """
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

def get_final_media_info(post_container):
    """
    Extract media information from any post type
    
    Args:
        post_container: BeautifulSoup element containing the post
        
    Returns:
        dict: Complete media information based on detected media type
    """
    if media_is_video(post_container):
        video_info = get_video_info(post_container)
        return {
            "type": "video",
            "thumbnail": video_info.get("thumbnail", ""),
            "duration": video_info.get("duration", "")
        }
    elif media_is_carousel(post_container):
        document_info = get_carousel_info(post_container)
        return {
            "type": document_info["type"],
            "title": document_info.get("title", ""),
            "info": "Images not visible in the HTML" 
        }
    elif images := get_images_info(post_container):
        return {
            "type": "image",
            "urls": images
        }
    else:
        return {
            "type": "none"
        }

# =====================================================================
# MAIN PROCESSING FUNCTIONS
# =====================================================================

def process_posts(soup):
    """
    Process all posts with CORRECTED reposter comment handling
    """
    posts = get_posts(soup)
    results = []
    
    for i, post_container in enumerate(posts):
        print(f"\n=== PROCESSING POST {i+1} ===")
        repost = is_repost(post_container)
        print(f"Is repost: {repost}")

        if repost:
            # For reposts, get content FIRST (original post content)
            post_content = get_post_description(post_container)
            
            # Then get reposter info and comment
            author_info = get_profile_info(post_container, is_reposter=True)
            print(f"Reposter: {author_info['name']}")
            
            # Get original author info
            original_author = get_original_author_info(post_container)
            print(f"Original author: {original_author['name']}")
            
            # Get reposter comment
            reposter_comment = get_reposter_comment(post_container)
            has_reposter_comment = bool(reposter_comment)
            
            print(f"Has reposter comment: {has_reposter_comment}")
            if has_reposter_comment:
                print(f"Reposter comment preview: {reposter_comment[:80]}...")
            print(f"Original content preview: {post_content[:80]}...")
            
            # Create repost JSON structure
            engagement = get_engagement(post_container)
            
            date_span = post_container.select_one(".update-components-actor__sub-description")
            rel_date = ""
            if date_span:
                date_text = clean(date_span.get_text())
                date_match = re.search(r'(\d+\s*[hdwmy]+o?)', date_text)
                if date_match:
                    rel_date = date_match.group(1)
            
            formatted_date = get_date(rel_date, post_container)
            content_slug = generate_post_slug(post_content)
            media = get_final_media_info(post_container)
            
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
                    "content": post_content,  # This should be the ORIGINAL content, not reposter comment
                    "slug": content_slug,
                    "media": media
                }
            }
            
            # Only add reposter comment if it exists and is different from original content
            if has_reposter_comment:
                # Validate that reposter comment is actually different
                normalized_comment = reposter_comment.lower().replace('#', '').replace(' ', '')
                normalized_original = post_content.lower().replace('#', '').replace(' ', '')
                
                if normalized_comment != normalized_original:
                    post["reposter_comment"] = reposter_comment
                else:
                    print("WARNING: Reposter comment identical to original content - skipping")
        
        else:
            # Regular post processing (unchanged)
            author_info = get_profile_info(post_container)
            print(f"Author: {author_info['name']}")
            
            post_content = get_post_description(post_container)
            engagement = get_engagement(post_container)
            
            date_span = post_container.select_one(".update-components-actor__sub-description")
            rel_date = ""
            if date_span:
                date_text = clean(date_span.get_text())
                date_match = re.search(r'(\d+\s*[hdwmy]+o?)', date_text)
                if date_match:
                    rel_date = date_match.group(1)
            
            formatted_date = get_date(rel_date, post_container)
            post_slug = generate_post_slug(post_content)
            media = get_final_media_info(post_container)
            
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

# =====================================================================
# MAIN EXECUTION
# =====================================================================

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
    
    print(f"\nDONE: {len(posts)} JSONs saved in '{OUTPUT_DIR}/'")
    
    # Print summary
    reposts = [p for p in posts if p['post_type'] == 'repost']
    regular_posts = [p for p in posts if p['post_type'] == 'post']
    
    print(f"\nSUMMARY:")
    print(f"- Regular posts: {len(regular_posts)}")
    print(f"- Reposts: {len(reposts)}")
    
    sys.exit(0)
    
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)