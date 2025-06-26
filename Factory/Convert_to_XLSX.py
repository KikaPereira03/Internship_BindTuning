import os
import json
import pandas as pd
import re
from pathlib import Path
from datetime import datetime
import numpy as np

# =============================================================================
# CONFIGURATION: Data Processing Settings
# =============================================================================
base_logs_folder = "_logs"  # Base folder containing all profile folders
xlsx_path = "dataset_results2.xlsx"  # Excel file optimized for ML

print("=" * 70)
print("LINKEDIN DATA PROCESSING - JSON TO EXCEL CONVERTER")
print("=" * 70)
print(f"Source folder: {base_logs_folder}")
print(f"Target Excel file: {xlsx_path}")
print("=" * 70)

# =============================================================================
# STEP 1: Load Existing Excel File or Create New Dataset
# =============================================================================
if os.path.exists(xlsx_path):
    print("Loading existing Excel file...")
    try:
        df_master = pd.read_excel(xlsx_path)
        print(f"   Successfully loaded Excel file with {len(df_master)} records")
    except Exception as e:
        print(f"   Error loading Excel file: {e}")
        print("   Creating fresh dataset instead...")
        df_master = pd.DataFrame()
    
    # Check and fix column compatibility issues
    if 'date' in df_master.columns and 'timestamp' not in df_master.columns:
        df_master = df_master.rename(columns={'date': 'timestamp'})
        print("   Converted 'date' column to 'timestamp' for compatibility")

    # Handle missing content_hash column in older Excel files
    if 'content_hash' not in df_master.columns:
        print("   Adding missing 'content_hash' column for duplicate detection...")
        # Create content_hash from existing content
        df_master['content_hash'] = df_master.get('content', '').apply(lambda x: create_content_hash(x))
        print("   Content hash column added successfully")

    # Build duplicate detection system from existing data
    print("   Building duplicate detection system...")
    try:
        existing_keys = set()
        for _, row in df_master.iterrows():
            author_name = str(row.get('author_name', '')).strip()
            timestamp = str(row.get('timestamp', '')).strip()
            content_hash = str(row.get('content_hash', '')).strip()
            
            # Create unique identifier key for each record
            key = f"{author_name}_{timestamp}_{content_hash}"
            existing_keys.add(key)
            
        print(f"   Found {len(df_master)} existing records")
        print(f"   Created {len(existing_keys)} unique detection keys")
    except Exception as e:
        print(f"   Warning: Error reading existing data: {e}")
        print("   Creating fresh dataset instead...")
        df_master = pd.DataFrame()
        existing_keys = set()
else:
    print("No existing Excel file found - creating new dataset...")
    df_master = pd.DataFrame()
    existing_keys = set()
    print("   New dataset initialized successfully")

print()  # Add spacing for readability

# =============================================================================
# HELPER FUNCTIONS: Content Analysis and Feature Extraction for ML
# =============================================================================

# --- TEXT ANALYSIS FUNCTIONS ---
def extract_hashtags(text):
    """Extract all hashtags from text content"""
    return re.findall(r"#(\w+)", text or "")

def count_hashtags(text):
    """Count number of hashtags in text"""
    return len(extract_hashtags(text))

def count_mentions(text):
    """Count number of @mentions in text"""
    return len(re.findall(r"@(\w+)", text or ""))

def count_words(text):
    """Count number of words in text"""
    return len((text or "").split())

def count_characters(text):
    """Count total characters in text"""
    return len(text or "")

def count_sentences(text):
    """Count number of sentences based on punctuation"""
    return len(re.findall(r'[.!?]+', text or ""))

# --- CONTENT PATTERN DETECTION ---
def has_call_to_action(text):
    """Detect if text contains call-to-action phrases"""
    cta_patterns = [
        r'\bclick\b', r'\bvisit\b', r'\bcheck out\b', r'\blearn more\b',
        r'\bregister\b', r'\bsign up\b', r'\bdownload\b', r'\bget\b',
        r'\bjoin\b', r'\bfollow\b', r'\bshare\b', r'\blike\b', r'\bcomment\b'
    ]
    return any(re.search(pattern, (text or "").lower()) for pattern in cta_patterns)

def has_question(text):
    """Check if text contains question marks (questions)"""
    return '?' in (text or "")

def has_url(text):
    """Detect if text contains URLs or web links"""
    return bool(re.search(r'http[s]?://|www\.|\.[a-z]{2,}/', text or ""))

def has_emojis(text):
    """Detect if text contains emojis or emoticons"""
    emoji_pattern = re.compile("["
        u"\U0001F600-\U0001F64F"  # emoticons
        u"\U0001F300-\U0001F5FF"  # symbols & pictographs
        u"\U0001F680-\U0001F6FF"  # transport & map
        u"\U0001F1E0-\U0001F1FF"  # flags
        "]+", flags=re.UNICODE)
    return bool(emoji_pattern.search(text or ""))

# --- DUPLICATE DETECTION ---
def create_content_hash(content):
    """Create MD5 hash for content to detect duplicate posts"""
    import hashlib
    return hashlib.md5((content or "").encode()).hexdigest()[:8]

# --- TEMPORAL FEATURE EXTRACTION ---
def extract_time_features(timestamp_str):
    """
    Extract comprehensive time-based features from timestamp for ML analysis
    Returns features like hour, day of week, time of day categories, etc.
    """
    try:
        if ' ' in timestamp_str:
            # Full timestamp format: "2025-05-21 14:23:47"
            dt = pd.to_datetime(timestamp_str)
        else:
            # Date-only format: "2025-05-21"
            dt = pd.to_datetime(timestamp_str)
        
        hour = dt.hour
        weekday = dt.weekday()  # 0=Monday, 6=Sunday
        
        return {
            # Basic date components
            'year': dt.year,
            'month': dt.month,
            'day': dt.day,
            'hour': hour,
            'weekday': weekday,
            
            # Weekend detection
            'is_weekend': weekday >= 5,
            
            # Time of day categories (useful for engagement prediction)
            'is_morning': 6 <= hour < 12,
            'is_afternoon': 12 <= hour < 18,
            'is_evening': 18 <= hour < 22,
            'is_night': hour >= 22 or hour < 6,
            
            # Calendar features
            'quarter': dt.quarter,
            'day_of_year': dt.dayofyear
        }
    except:
        # Return null values for invalid/unparseable dates
        return {
            'year': None, 'month': None, 'day': None, 'hour': None,
            'weekday': None, 'is_weekend': None, 'is_morning': None,
            'is_afternoon': None, 'is_evening': None, 'is_night': None,
            'quarter': None, 'day_of_year': None
        }

# --- ENGAGEMENT METRICS CALCULATION ---
def calculate_engagement_ratios(likes, comments, reposts):
    """
    Calculate comprehensive engagement metrics and ratios for ML analysis
    Used to derive engagement patterns and performance indicators
    """
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
    
    # Calculate weighted engagement score (reposts weighted higher)
    engagement_score = likes + comments + 2 * reposts
    
    # Categorize engagement level for ML classification
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

# =============================================================================
# MAIN DATA PROCESSING FUNCTION: JSON to ML-Optimized Record Conversion
# =============================================================================
def parse_post_ml_optimized(json_data):
    """
    Parse JSON post data into ML-optimized record with comprehensive features
    Handles both regular posts and reposts with different data structures
    """
    post_type = json_data.get("post_type", "")
    post_date = json_data.get("date", "")
    
    # Initialize comprehensive ML record structure
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
    
    # Extract temporal features from post timestamp
    time_features = extract_time_features(post_date)
    record.update(time_features)
    
    # ==========================================================================
    # PROCESSING LOGIC: Handle Different Post Types (Regular vs Repost)
    # ==========================================================================
    
    if post_type == "repost":
        # --- REPOST PROCESSING: Extract both reposter and original author info ---
        reposter = json_data.get("author", {})
        reposter_comment = json_data.get("reposter_comment", "")
        post_data = json_data.get("original_post", {})
        original_author = post_data.get("author", {})
        original_content = post_data.get("content", "")
        
        # Reposter information (person who shared the post)
        record["author_name"] = reposter.get("name", "")
        record["author_description"] = reposter.get("description", "")
        record["author_pic"] = reposter.get("pic", "")
        
        # Reposter's comment on the shared post
        record["reposter_comment"] = reposter_comment
        record["has_reposter_comment"] = bool(reposter_comment)
        
        # Original author information (person who created the post)
        record["original_author_name"] = original_author.get("name", "")
        record["original_author_description"] = original_author.get("description", "")
        record["original_author_pic"] = original_author.get("pic", "")
        
        # Use original content for ML analysis (main content to analyze)
        record["content"] = original_content
        
        # Extract media information from original post
        media = post_data.get("media", {})
        
    else:
        # --- REGULAR POST PROCESSING: Direct post from author ---
        author = json_data.get("author", {})
        content = json_data.get("content", "")
        
        # Author information
        record["author_name"] = author.get("name", "")
        record["author_description"] = author.get("description", "")
        record["author_pic"] = author.get("pic", "")
        
        # Post content
        record["content"] = content
        
        # Extract media information from post
        media = json_data.get("media", {})
    
    # ==========================================================================
    # CONTENT FEATURE EXTRACTION: Analyze text content for ML features
    # ==========================================================================
    content = record["content"]
    record["content_hash"] = create_content_hash(content)
    record["content_length"] = count_characters(content)
    record["word_count"] = count_words(content)
    record["hashtag_count"] = count_hashtags(content)
    record["has_call_to_action"] = has_call_to_action(content)
    record["has_emojis"] = has_emojis(content)
    
    # Extract hashtags as comma-separated list
    hashtags_list = extract_hashtags(content)
    record["hashtags"] = ", ".join(hashtags_list)
    
    # ==========================================================================
    # MEDIA FEATURE EXTRACTION: Analyze attached media content
    # ==========================================================================
    media_type = media.get("type", "")
    record["has_media"] = media_type not in ["", "none"]
    record["has_video"] = media_type == "video"
    record["has_image"] = media_type == "image"
    record["has_carousel"] = media_type == "carousel"
    
    # Extract media URLs as comma-separated list
    media_urls = media.get("urls") if isinstance(media.get("urls"), list) else [media.get("thumbnail")] if media.get("thumbnail") else []
    record["media_urls"] = ", ".join(media_urls)
    
    # ==========================================================================
    # ENGAGEMENT METRICS EXTRACTION: Social interaction data
    # ==========================================================================
    engagement = json_data.get("social_engagement", {})
    likes = engagement.get("likes", 0)
    comments = engagement.get("comments", 0)
    reposts_count = engagement.get("reposts", 0)
    
    # Store engagement numbers
    record["likes"] = likes
    record["comments"] = comments
    record["reposts"] = reposts_count
    
    # Calculate weighted engagement score (reposts have higher weight)
    record["engagement_score"] = likes + comments + 2 * reposts_count
    
    # Categorize engagement level for ML classification
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

# =============================================================================
# FILE SYSTEM OPERATIONS: JSON File Discovery and Processing
# =============================================================================
def find_all_json_files(base_folder):
    """
    Recursively find all JSON files in the logs directory structure
    Searches through all profile folders and subfolders
    """
    json_files = []
    
    if not os.path.exists(base_folder):
        print(f"Base folder '{base_folder}' not found!")
        return json_files
    
    print(f"Scanning directory structure in '{base_folder}'...")
    
    for root, dirs, files in os.walk(base_folder):
        for file in files:
            if file.endswith(".json"):
                full_path = os.path.join(root, file)
                json_files.append(full_path)
    
    print(f"Found {len(json_files)} JSON files across all directories")
    return json_files

# =============================================================================
# STEP 2: Main Processing - Scan for JSON Files and Process Data
# =============================================================================
print()
print("Starting JSON file processing...")

# Discover all JSON files in the logs directory
all_json_files = find_all_json_files(base_logs_folder)

if not all_json_files:
    print("No JSON files found! Exiting...")
    exit(1)

# Initialize processing counters
new_records = []
processed_files = 0
skipped_files = 0

print(f"\nProcessing {len(all_json_files)} JSON files for ML dataset...")
print("-" * 50)

for file_path in all_json_files:
    try:
        # Load and parse JSON file
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            record = parse_post_ml_optimized(data)
            
            # Create unique identifier for duplicate detection
            author_name = str(record.get('author_name', '')).strip()
            timestamp = str(record.get('timestamp', '')).strip()
            content_hash = str(record.get('content_hash', '')).strip()
            
            key = f"{author_name}_{timestamp}_{content_hash}"
            
            # Check if this record already exists
            if key not in existing_keys:
                new_records.append(record)
                existing_keys.add(key)
                processed_files += 1
                
                # Show first few new records being added
                if processed_files <= 3:
                    print(f"   Adding: {author_name[:30]}... | {timestamp} | {content_hash}")
            else:
                skipped_files += 1
                
                # Show first few duplicates being skipped
                if skipped_files <= 3:
                    print(f"   Skipping duplicate: {author_name[:30]}... | {timestamp} | {content_hash}")

    except Exception as e:
        print(f"  Error processing {file_path}: {e}")
        skipped_files += 1

# =============================================================================
# STEP 3: Processing Summary and Results
# =============================================================================
print()
print("-" * 50)
print(" PROCESSING SUMMARY:")
print(f"   Total files scanned: {len(all_json_files)}")
print(f"   New records added: {len(new_records)}")
print(f"   Duplicates skipped: {skipped_files}")
print(f"   Files with errors: {skipped_files - (len(all_json_files) - processed_files - len(new_records))}")
print("-" * 50)

# =============================================================================
# STEP 4: Excel File Creation and ML Dataset Optimization
# =============================================================================
if new_records:
    print()
    print(" Updating ML training dataset...")
    
    # Combine new records with existing data
    df_new = pd.DataFrame(new_records)
    df_combined = pd.concat([df_master, df_new], ignore_index=True)

    print(f"   Sorting records by timestamp (newest first)...")
    # Sort by timestamp (newest first) for better data organization
    df_combined['timestamp'] = pd.to_datetime(df_combined['timestamp'])
    df_combined = df_combined.sort_values('timestamp', ascending=False)
    df_combined['timestamp'] = df_combined['timestamp'].dt.strftime('%Y-%m-%d %H:%M:%S')

    print(f"   Organizing columns for ML optimization...")
    # Define ML-optimized column order (most important features first)
    ml_column_order = [
        # === AUTHOR/REPOSTER INFORMATION ===
        'author_name', 'author_description', 'author_pic',

        # === POST CONTEXT AND TYPE ===
        'timestamp', 'post_type', 'is_repost',
        'has_reposter_comment', 'reposter_comment',
        
        # === ORIGINAL AUTHOR INFO (FOR REPOSTS) ===
        'original_author_name', 'original_author_description', 'original_author_pic',
        
        # === CONTENT FEATURES (MOST IMPORTANT FOR ML) ===
        'content', 'content_length', 'word_count',
        'hashtags', 'hashtag_count', 'has_call_to_action', 'has_emojis',
        
        # === ENGAGEMENT METRICS (TARGET VARIABLES) ===
        'likes', 'comments', 'reposts', 'engagement_score', 'engagement_rate_category',
        
        # === MEDIA FEATURES ===
        'has_media', 'has_video', 'has_image', 'has_carousel', 'media_urls',
        
        # === TEMPORAL FEATURES ===
        'hour', 'is_morning', 'is_afternoon', 'is_evening', 'is_night',
        'weekday', 'is_weekend', 'month',
        
        # === TECHNICAL IDENTIFIERS ===
        'content_hash', 'year', 'day', 'day_of_year'
    ]
    
    # Ensure all columns exist in the dataset
    for col in ml_column_order:
        if col not in df_combined.columns:
            df_combined[col] = None
    
    # Reorder columns according to ML optimization
    df_combined = df_combined[ml_column_order]
    
    print(f"    Saving Excel file...")
    # Save the optimized dataset
    df_combined.to_excel(xlsx_path, index=False)
    
    print()
    print("=" * 70)
    print(" DATASET UPDATE COMPLETED SUCCESSFULLY!")
    print(f" File location: {xlsx_path}")
    print(f" Total records: {len(df_combined)} (was {len(df_master)}, added {len(new_records)})")
    print(f" Columns optimized: {len(ml_column_order)} features organized for ML")
    print("=" * 70)
    
else:
    print()
    print("=" * 70)
    print("  NO NEW DATA TO PROCESS")
    print(" Dataset is already up to date - no new posts found")
    print(f" Current dataset: {xlsx_path}")
    print(f" Total records maintained: {len(df_master)}")
    print("=" * 70)

print()
print(" Processing completed successfully!")