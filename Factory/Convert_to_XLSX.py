import os
import json
import pandas as pd
import re
from pathlib import Path
from datetime import datetime
import numpy as np

# Configuration
base_logs_folder = "_logs"  # Base folder containing all profile folders
xlsx_path = "dataset_results2.xlsx"  # Excel file optimized for ML

print(f"Looking for JSON files in: {base_logs_folder}")
print(f"Excel file will be saved to: {xlsx_path}")

if os.path.exists(xlsx_path):
    print("Loading existing Excel file...")
    df_master = pd.read_excel(xlsx_path)
    
    if 'date' in df_master.columns and 'timestamp' not in df_master.columns:
        df_master = df_master.rename(columns={'date': 'timestamp'})
        print("   Converted 'date' column to 'timestamp' for compatibility")
    
    # Handle missing content_hash column in old files
    if 'content_hash' not in df_master.columns:
        # Create content_hash from existing content
        df_master['content_hash'] = df_master.get('content', '').apply(lambda x: create_content_hash(x))
        print("   Added missing 'content_hash' column")
    
    try:
        existing_keys = set()
        for _, row in df_master.iterrows():
            author_name = str(row.get('author_name', '')).strip()
            timestamp = str(row.get('timestamp', '')).strip()
            content_hash = str(row.get('content_hash', '')).strip()
            
            # Create consistent key
            key = f"{author_name}_{timestamp}_{content_hash}"
            existing_keys.add(key)
            
        print(f"Found {len(df_master)} existing records")
        print(f"Created {len(existing_keys)} unique detection keys")
    except Exception as e:
        print(f"Warning: Error reading existing data: {e}")
        print("Creating fresh dataset...")
        df_master = pd.DataFrame()
        existing_keys = set()
else:
    print("Creating new Excel file...")
    df_master = pd.DataFrame()
    existing_keys = set()

# Enhanced helper functions for ML features
def extract_hashtags(text):
    return re.findall(r"#(\w+)", text or "")

def count_hashtags(text):
    return len(extract_hashtags(text))

def count_mentions(text):
    return len(re.findall(r"@(\w+)", text or ""))

def count_words(text):
    return len((text or "").split())

def count_characters(text):
    return len(text or "")

def count_sentences(text):
    return len(re.findall(r'[.!?]+', text or ""))

def has_call_to_action(text):
    cta_patterns = [
        r'\bclick\b', r'\bvisit\b', r'\bcheck out\b', r'\blearn more\b',
        r'\bregister\b', r'\bsign up\b', r'\bdownload\b', r'\bget\b',
        r'\bjoin\b', r'\bfollow\b', r'\bshare\b', r'\blike\b', r'\bcomment\b'
    ]
    return any(re.search(pattern, (text or "").lower()) for pattern in cta_patterns)

def has_question(text):
    return '?' in (text or "")

def has_url(text):
    return bool(re.search(r'http[s]?://|www\.|\.[a-z]{2,}/', text or ""))

def has_emojis(text):
    emoji_pattern = re.compile("["
        u"\U0001F600-\U0001F64F"  # emoticons
        u"\U0001F300-\U0001F5FF"  # symbols & pictographs
        u"\U0001F680-\U0001F6FF"  # transport & map
        u"\U0001F1E0-\U0001F1FF"  # flags
        "]+", flags=re.UNICODE)
    return bool(emoji_pattern.search(text or ""))

def create_content_hash(content):
    """Create a hash for content to detect duplicates"""
    import hashlib
    return hashlib.md5((content or "").encode()).hexdigest()[:8]

def extract_time_features(timestamp_str):
    """Extract time-based features from timestamp"""
    try:
        if ' ' in timestamp_str:
            # Full timestamp: "2025-05-21 14:23:47"
            dt = pd.to_datetime(timestamp_str)
        else:
            # Date only: "2025-05-21"
            dt = pd.to_datetime(timestamp_str)
        
        hour = dt.hour
        weekday = dt.weekday()  # 0=Monday, 6=Sunday
        
        return {
            'year': dt.year,
            'month': dt.month,
            'day': dt.day,
            'hour': hour,
            'weekday': weekday,
            'is_weekend': weekday >= 5,
            'is_morning': 6 <= hour < 12,
            'is_afternoon': 12 <= hour < 18,
            'is_evening': 18 <= hour < 22,
            'is_night': hour >= 22 or hour < 6,
            'quarter': dt.quarter,
            'day_of_year': dt.dayofyear
        }
    except:
        # Fallback for invalid dates
        return {
            'year': None, 'month': None, 'day': None, 'hour': None,
            'weekday': None, 'is_weekend': None, 'is_morning': None,
            'is_afternoon': None, 'is_evening': None, 'is_night': None,
            'quarter': None, 'day_of_year': None
        }

def calculate_engagement_ratios(likes, comments, reposts):
    """Calculate engagement ratios and metrics"""
    total_engagement = likes + comments + reposts
    if total_engagement == 0:
        return {
            'total_engagement': 0,
            'engagement_score': 0,
            'likes_ratio': 0,
            'comments_ratio': 0,
            'reposts_ratio': 0,
            'comment_like_ratio': 0,
            'repost_like_ratio': 0,
            'engagement_rate_category': 'none'
        }
    
    engagement_score = likes + comments + 2 * reposts
    
    # Categorize engagement level
    if total_engagement >= 100:
        engagement_category = 'high'
    elif total_engagement >= 20:
        engagement_category = 'medium'
    elif total_engagement >= 5:
        engagement_category = 'low'
    else:
        engagement_category = 'minimal'
    
    return {
        'total_engagement': total_engagement,
        'engagement_score': engagement_score,
        'likes_ratio': likes / total_engagement,
        'comments_ratio': comments / total_engagement,
        'reposts_ratio': reposts / total_engagement,
        'comment_like_ratio': comments / max(likes, 1),
        'repost_like_ratio': reposts / max(likes, 1),
        'engagement_rate_category': engagement_category
    }

def parse_post_ml_optimized(json_data):
    """Parse JSON post data into ML-optimized record"""
    post_type = json_data.get("post_type", "")
    post_date = json_data.get("date", "")
    
    # Initialize ML-optimized record
    record = {
        # === CORE IDENTIFIERS ===
        "content_hash": "",
        "timestamp": post_date,
        
        # === POST METADATA ===
        "post_type": post_type,
        "is_repost": post_type == "repost",
        
        # === AUTHOR FEATURES ===
        "author_name": "",
        "author_description": "",
        "author_pic": "",  
        
        # === CONTENT FEATURES ===
        "content": "",
        "content_length": 0,
        "word_count": 0,
        "hashtag_count": 0,
        "hashtags": "", 
        "has_call_to_action": False,
        "has_emojis": False,
        
        # === REPOST FEATURES ===
        "reposter_comment": "", 
        "has_reposter_comment": False,
        "original_author_name": "",
        "original_author_description": "",  
        "original_author_pic": "",  
        
        # === ENGAGEMENT FEATURES (TARGET VARIABLES) ===
        "likes": 0,
        "comments": 0,
        "reposts": 0,
        "engagement_score": 0,
        "engagement_rate_category": "",
        
        # === MEDIA FEATURES ===
        "has_media": False,
        "has_video": False,
        "has_image": False,
        "has_carousel": False,
        "media_urls": "",  
        
        # === TEMPORAL FEATURES ===
        "year": None,
        "month": None,
        "day": None,
        "hour": None,
        "weekday": None,
        "is_weekend": None,
        "is_morning": None,
        "is_afternoon": None,
        "is_evening": None,
        "is_night": None,
        "quarter": None,
        "day_of_year": None
    }
    
    # Extract time features
    time_features = extract_time_features(post_date)
    record.update(time_features)
    
    if post_type == "repost":
        # REPOST PROCESSING
        reposter = json_data.get("author", {})
        reposter_comment = json_data.get("reposter_comment", "")
        post_data = json_data.get("original_post", {})
        original_author = post_data.get("author", {})
        original_content = post_data.get("content", "")
        
        # Author info (reposter)
        record["author_name"] = reposter.get("name", "")
        record["author_description"] = reposter.get("description", "")  # ADDED BACK
        record["author_pic"] = reposter.get("pic", "")  # ADDED BACK
        
        # Reposter comment features
        record["reposter_comment"] = reposter_comment  # FIXED - actual comment text
        record["has_reposter_comment"] = bool(reposter_comment)
        
        # Original author and content
        record["original_author_name"] = original_author.get("name", "")
        record["original_author_description"] = original_author.get("description", "")  # ADDED BACK
        record["original_author_pic"] = original_author.get("pic", "")  # ADDED BACK
        
        # Use original content for analysis (clean ML approach)
        record["content"] = original_content
        
        # Media from original post
        media = post_data.get("media", {})
        
    else:
        # REGULAR POST PROCESSING
        author = json_data.get("author", {})
        content = json_data.get("content", "")
        
        record["author_name"] = author.get("name", "")
        record["author_description"] = author.get("description", "")  # ADDED BACK
        record["author_pic"] = author.get("pic", "")  # ADDED BACK
        record["content"] = content
        
        media = json_data.get("media", {})
    
    # Content features (for both post types)
    content = record["content"]
    record["content_hash"] = create_content_hash(content)
    record["content_length"] = count_characters(content)
    record["word_count"] = count_words(content)
    record["hashtag_count"] = count_hashtags(content)
    record["has_call_to_action"] = has_call_to_action(content)
    record["has_emojis"] = has_emojis(content)
    
    # Extract hashtags list (ADDED BACK)
    hashtags_list = extract_hashtags(content)
    record["hashtags"] = ", ".join(hashtags_list)
    
    # Media features
    media_type = media.get("type", "")
    record["has_media"] = media_type not in ["", "none"]
    record["has_video"] = media_type == "video"
    record["has_image"] = media_type == "image"
    record["has_carousel"] = media_type == "carousel"
    
    # Media URLs (ADDED BACK)
    media_urls = media.get("urls") if isinstance(media.get("urls"), list) else [media.get("thumbnail")] if media.get("thumbnail") else []
    record["media_urls"] = ", ".join(media_urls)
    
    # Engagement features
    engagement = json_data.get("social_engagement", {})
    likes = engagement.get("likes", 0)
    comments = engagement.get("comments", 0)
    reposts_count = engagement.get("reposts", 0)
    
    record["likes"] = likes
    record["comments"] = comments
    record["reposts"] = reposts_count
    
    # Calculate basic engagement metrics (simplified)
    record["engagement_score"] = likes + comments + 2 * reposts_count
    
    # Simple engagement categorization
    total_engagement = likes + comments + reposts_count
    if total_engagement >= 100:
        record["engagement_rate_category"] = 'high'
    elif total_engagement >= 20:
        record["engagement_rate_category"] = 'medium'
    elif total_engagement >= 5:
        record["engagement_rate_category"] = 'low'
    else:
        record["engagement_rate_category"] = 'minimal'
    
    return record

# Find all JSON files
def find_all_json_files(base_folder):
    """Find all JSON files in all subdirectories"""
    json_files = []
    
    if not os.path.exists(base_folder):
        print(f"Base folder '{base_folder}' not found!")
        return json_files
    
    for root, dirs, files in os.walk(base_folder):
        for file in files:
            if file.endswith(".json"):
                full_path = os.path.join(root, file)
                json_files.append(full_path)
    
    return json_files

# Main processing
print("Scanning for JSON files...")
all_json_files = find_all_json_files(base_logs_folder)
print(f"Found {len(all_json_files)} JSON files across all profiles")

# Process all JSON files
new_records = []
processed_files = 0
skipped_files = 0

print(f"\nProcessing JSON files for ML dataset...")

for file_path in all_json_files:
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            record = parse_post_ml_optimized(data)
            
            author_name = str(record.get('author_name', '')).strip()
            timestamp = str(record.get('timestamp', '')).strip()
            content_hash = str(record.get('content_hash', '')).strip()
            
            key = f"{author_name}_{timestamp}_{content_hash}"
            
            if key not in existing_keys:
                new_records.append(record)
                existing_keys.add(key)
                processed_files += 1
                
                # Print first few new records
                if processed_files <= 3:
                    print(f"   Adding new record: {author_name[:30]}... | {timestamp} | {content_hash}")
            else:
                skipped_files += 1
                
                # Print first few skipped records
                if skipped_files <= 3:
                    print(f"   Skipping duplicate: {author_name[:30]}... | {timestamp} | {content_hash}")
                
    except Exception as e:
        print(f"Skipped {file_path}: {e}")
        skipped_files += 1

print(f"\nProcessing Results:")
print(f"   New records: {len(new_records)}")
print(f"   Duplicates skipped: {skipped_files}")
print(f"   Total files processed: {processed_files + skipped_files}")

# Save ML-optimized Excel file
if new_records:
    print(f"\nUpdating ML training dataset...")
    df_new = pd.DataFrame(new_records)
    df_combined = pd.concat([df_master, df_new], ignore_index=True)
    
    # Sort by timestamp (newest first)
    df_combined['timestamp'] = pd.to_datetime(df_combined['timestamp'])
    df_combined = df_combined.sort_values('timestamp', ascending=False)
    df_combined['timestamp'] = df_combined['timestamp'].dt.strftime('%Y-%m-%d %H:%M:%S')


    ml_column_order = [
        # === REPOSTER/AUTHOR POST INFO===
        'author_name', 'author_description', 'author_pic',

        # === POST CONTEXT ===
        'timestamp', 'post_type', 'is_repost',
        'has_reposter_comment', 'reposter_comment',
        
        # === ORIGINAL AUTHOR INFO (IF REPOST) ===
        'original_author_name', 'original_author_description', 'original_author_pic',
        
        # === CONTENT (MOST IMPORTANT) ===
        'content', 'content_length', 'word_count',
        'hashtags', 'hashtag_count', 'has_call_to_action', 'has_emojis',
        
        # === ENGAGEMENT RESULTS ===
        'likes', 'comments', 'reposts', 'engagement_score', 'engagement_rate_category',
        
        # === MEDIA INFORMATION ===
        'has_media', 'has_video', 'has_image', 'has_carousel', 'media_urls',
        
        # === TIMING CONTEXT ===
        'hour', 'is_morning', 'is_afternoon', 'is_evening', 'is_night',
        'weekday', 'is_weekend', 'month',
        
        # === TECHNICAL IDENTIFIERS ===
        'content_hash', 'year', 'day', 'day_of_year'
    ]
    
    
    # Ensure all columns exist and reorder
    for col in ml_column_order:
        if col not in df_combined.columns:
            df_combined[col] = None
    
    df_combined = df_combined[ml_column_order]
    
    df_combined.to_excel(xlsx_path, index=False)
    print(f"Dataset updated: '{xlsx_path}'")
    print(f"Total records: {len(df_combined)} (was {len(df_master)}, added {len(new_records)})")
    
else:
    print("\nNo new posts to add - dataset is up to date")




