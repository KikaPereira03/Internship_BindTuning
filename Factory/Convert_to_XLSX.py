import os
import json
import pandas as pd
import re

# Path config
json_folder = "_logs/Daniel Anderson/2025-05-15_15-08/Activity" 
xlsx_path = "full_posts_all_fields.xlsx"

# Load existing Excel (if it exists)
if os.path.exists(xlsx_path):
    df_master = pd.read_excel(xlsx_path)
    existing_keys = set(
        df_master.apply(lambda row: f"{row['author_name']}_{row['date']}_{row['content']}", axis=1)
    )
else:
    df_master = pd.DataFrame()
    existing_keys = set()

# Helpers
def extract_hashtags(text):
    return re.findall(r"#(\w+)", text or "")

def calculate_engagement(likes, comments, reposts):
    return likes + comments + 2 * reposts

def parse_post(json_data):
    post_type = json_data.get("post_type", "")
    post_date = json_data.get("date", "")
    slug = json_data.get("slug", "")
    media_type = ""
    media_urls = []
    media_duration = ""
    reposter_comment = ""
    
    if post_type == "repost":
        reposter = json_data.get("author", {})
        reposter_comment = json_data.get("reposter_comment", "")
        post_data = json_data.get("original_post", {})
        original_author = post_data.get("author", {})
        original_content = post_data.get("content", "")
        content = f"{reposter.get('name', '')} said: {reposter_comment}\n\nOriginally by {original_author.get('name', '')}: {original_content}"
        media = post_data.get("media", {})
        media_type = media.get("type", "")
        media_duration = media.get("duration", "")
        media_urls = media.get("urls") if isinstance(media.get("urls"), list) else [media.get("thumbnail")] if media.get("thumbnail") else []

        author = reposter
    else:
        author = json_data.get("author", {})
        content = json_data.get("content", "")
        media = json_data.get("media", {})
        media_type = media.get("type", "")
        media_duration = media.get("duration", "")
        media_urls = media.get("urls") if isinstance(media.get("urls"), list) else [media.get("thumbnail")] if media.get("thumbnail") else []

    engagement = json_data.get("social_engagement", json_data.get("social_engagment", {}))
    likes = engagement.get("likes", 0)
    comments = engagement.get("comments", 0)
    reposts = engagement.get("reposts", 0)

    return {
        "post_type": post_type,
        "date": post_date,
        "slug": slug,
        "author_name": author.get("name", ""),
        "author_description": author.get("description", ""),
        "author_slug": author.get("slug", ""),
        "author_pic": author.get("pic", ""),
        "content": content,
        "reposter_comment": reposter_comment,
        "hashtags": ", ".join(extract_hashtags(content)),
        "likes": likes,
        "comments": comments,
        "reposts": reposts,
        "engagement_score": calculate_engagement(likes, comments, reposts),
        "media_type": media_type,
        "media_urls": ", ".join(media_urls),
        "media_duration": media_duration
    }

# Process new JSONs
new_records = []
for filename in os.listdir(json_folder):
    if filename.endswith(".json"):
        file_path = os.path.join(json_folder, filename)
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                record = parse_post(data)
                key = f"{record['author_name']}_{record['date']}_{record['content']}"
                if key not in existing_keys:
                    new_records.append(record)
                    existing_keys.add(key)
        except Exception as e:
            print(f"⚠️ Skipped {filename}: {e}")

# Save updated Excel file
if new_records:
    df_new = pd.DataFrame(new_records)
    df_combined = pd.concat([df_master, df_new], ignore_index=True)
    df_combined.to_excel(xlsx_path, index=False)
    print(f"✅ Added {len(df_new)} new posts to '{xlsx_path}'")
else:
    print("✅ No new posts to add.")
