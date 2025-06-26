import os
import subprocess
import sys
from pathlib import Path

# Configuration
BASE_LOGS_FOLDER = "../_logs"  # Base folder
CREATE_JSON_SCRIPT = "CreateJSON.py"  # Path to your CreateJSON.py script

def find_latest_posts_files(base_folder):
    """
    Find all LatestPosts.html files in the directory structure
    
    Args:
        base_folder (str): Base folder to search in
        
    Returns:
        list: List of tuples (html_file_path, output_directory)
    """
    html_files = []
    
    if not os.path.exists(base_folder):
        print(f"Base folder '{base_folder}' not found!")
        return html_files
    
    # Walk through all subdirectories
    for root, dirs, files in os.walk(base_folder):
        for file in files:
            if file == "LatestPosts.html":
                html_path = os.path.join(root, file)
                # Output directory is the same directory as the HTML file
                output_dir = root
                html_files.append((html_path, output_dir))
    
    return html_files

def run_create_json(html_file, output_dir):
    """
    Run CreateJSON.py on a specific HTML file
    
    Args:
        html_file (str): Path to the HTML file
        output_dir (str): Output directory for JSON files
        
    Returns:
        bool: True if successful, False if failed
    """
    try:
        print(f"Processing: {html_file}")
        print(f"Output to: {output_dir}")
        
        # Run the CreateJSON.py script
        result = subprocess.run([
            sys.executable,  # Use the same Python interpreter
            CREATE_JSON_SCRIPT,
            html_file,
            output_dir
        ], capture_output=True, text=True, timeout=300)  # 5 minute timeout
        
        if result.returncode == 0:
            print(f"✅ Success: {html_file}")
            # Print any output from the script
            if result.stdout.strip():
                print(f"   Output: {result.stdout.strip()}")
            return True
        else:
            print(f"Failed: {html_file}")
            print(f"Error: {result.stderr.strip()}")
            return False
            
    except subprocess.TimeoutExpired:
        print(f"Timeout: {html_file} (took more than 5 minutes)")
        return False
    except Exception as e:
        print(f"Exception: {html_file} - {str(e)}")
        return False

def main():
    """
    Main function to process all LatestPosts.html files
    """
    print("Batch Processing LinkedIn Posts")
    print("=" * 50)
    
    # Check if CreateJSON.py exists
    if not os.path.exists(CREATE_JSON_SCRIPT):
        print(f"Error: {CREATE_JSON_SCRIPT} not found in current directory!")
        print("   Make sure you're running this script from the same folder as CreateJSON.py")
        sys.exit(1)
    
    # Find all HTML files
    print(f"Searching for LatestPosts.html files in: {BASE_LOGS_FOLDER}")
    html_files = find_latest_posts_files(BASE_LOGS_FOLDER)

    
    print(f"Found {len(html_files)} HTML files to process:")
    
    # Show all files that will be processed
    for i, (html_file, output_dir) in enumerate(html_files, 1):
        # Extract profile name from path
        path_parts = Path(html_file).parts
        profile_name = "Unknown"
        if len(path_parts) >= 2:
            profile_name = path_parts[-4] if len(path_parts) >= 4 else path_parts[-2]
        
        print(f"   {i:2d}. {profile_name} → {html_file}")
    
    print("\n" + "=" * 50)
    
    # Ask for confirmation
    response = input("Proceed with processing all files? (y/N): ").strip().lower()
    if response not in ['y', 'yes']:
        print("Cancelled by user")
        sys.exit(0)
    
    print("\nStarting batch processing...")
    print("=" * 50)
    
    # Process each file
    successful = 0
    failed = 0
    
    for i, (html_file, output_dir) in enumerate(html_files, 1):
        print(f"\n[{i}/{len(html_files)}] ", end="")
        
        if run_create_json(html_file, output_dir):
            successful += 1
        else:
            failed += 1
    
    # Final summary
    print("\n" + "=" * 50)
    print("BATCH PROCESSING COMPLETE!")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    print(f"Total: {len(html_files)}")
    
    if failed > 0:
        print(f"\n  {failed} files failed to process. Check the error messages above.")
    
    if successful > 0:
        print(f"\n{successful} profiles processed successfully!")
        print("Next step: Run Convert_to_XLSX.py to consolidate all JSON files into Excel")
        print(f"   Command: python Convert_to_XLSX.py")

if __name__ == "__main__":
    main()