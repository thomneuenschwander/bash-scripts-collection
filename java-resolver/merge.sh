#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [-a | -r] -d DEST_FILE SOURCE_FILES..."
    echo ""
    echo "Options:"
    echo "  -a                Add modules to the destination file (default operation)"
    echo "  -r                Remove modules from the destination file"
    echo "  -d DEST_FILE      Specify the destination file"
    echo "  SOURCE_FILES      List of source Java files to process"
    exit 1
}

# Default operation is to add modules
OPERATION="add"
DEST_FILE=""

# Parse command-line options using getopts
while getopts ":ard:" opt; do
    case "$opt" in
        a)
            OPERATION="add"
            ;;
        r)
            OPERATION="remove"
            ;;
        d)
            DEST_FILE="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND - 1))

# Check if the destination file and source files are provided
if [[ -z "$DEST_FILE" ]] || [[ $# -lt 1 ]]; then
    usage
fi

# Collect the source files
SOURCE_FILES=("$@")

# Function to merge imports and remove duplicates
merge_imports() {
    local imports="$1"
    echo "$imports" | sort | uniq
}

# Function to process a source file for adding
process_source_file_add() {
    local src_file="$1"
    local imports content

    # Check if the source file exists
    if [[ ! -f "$src_file" ]]; then
        echo "Error: Source file '$src_file' does not exist."
        return 1
    fi

    # Extract imports and content from the source file
    imports=$(grep '^import ' "$src_file")
    content=$(sed '/^package /d; /^import /d; s/^public \(class\|interface\|enum\|record\)/\1/' "$src_file")

    # Append the content to the temporary file
    echo "$content" >> "$TEMP_CONTENT_FILE"

    # Return the imports
    echo "$imports"
}

# Function to process a source file for removal
process_source_file_remove() {
    local src_file="$1"
    local class_name

    # Check if the source file exists
    if [[ ! -f "$src_file" ]]; then
        echo "Error: Source file '$src_file' does not exist."
        return 1
    fi

    # Extract the class name from the file name
    class_name=$(basename "$src_file" .java)

    # Remove the class definition from the destination file
    sed -i "/^\s*\(public\s\)\?\(class\|interface\|enum\|record\)\s\+$class_name\b/,/^}/d" "$DEST_FILE"
}

# Main function to add modules
add_modules() {
    local all_imports dest_imports src_imports

    # Ensure the destination file exists
    if [[ ! -f "$DEST_FILE" ]]; then
        echo "Creating destination file '$DEST_FILE'."
        touch "$DEST_FILE"
    fi

    # Extract existing imports from the destination file
    dest_imports=$(grep '^import ' "$DEST_FILE")

    # Temporary file to collect content
    TEMP_CONTENT_FILE=$(mktemp)

    # Initialize all_imports with existing destination imports
    all_imports="$dest_imports"

    # Process each source file
    for src_file in "${SOURCE_FILES[@]}"; do
        src_imports=$(process_source_file_add "$src_file")
        all_imports=$(echo -e "$all_imports\n$src_imports")
    done

    # Merge and sort imports
    all_imports=$(merge_imports "$all_imports")

    # Remove existing imports from the destination file
    sed -i '/^import /d' "$DEST_FILE"

    # Write merged imports and existing content to the destination file
    {
        echo "$all_imports"
        # Exclude package declarations from the destination file
        sed '/^package /d' "$DEST_FILE"
        # Append the new content
        cat "$TEMP_CONTENT_FILE"
    } > "${DEST_FILE}.tmp" && mv "${DEST_FILE}.tmp" "$DEST_FILE"

    # Clean up
    rm "$TEMP_CONTENT_FILE"

    echo "Modules added to '$DEST_FILE'."
}

# Main function to remove modules
remove_modules() {
    # Ensure the destination file exists
    if [[ ! -f "$DEST_FILE" ]]; then
        echo "Error: Destination file '$DEST_FILE' does not exist."
        exit 1
    fi

    # Process each source file for removal
    for src_file in "${SOURCE_FILES[@]}"; do
        process_source_file_remove "$src_file"
    done

    # Clean up imports
    clean_imports

    echo "Modules removed from '$DEST_FILE'."
}

# Function to clean up unused imports
clean_imports() {
    local used_classes imports new_imports

    # Collect all used class names from the destination file
    used_classes=$(grep -o '\b[A-Z][A-Za-z0-9_]*\b' "$DEST_FILE" | sort | uniq)

    # Collect all import statements
    imports=$(grep '^import ' "$DEST_FILE")

    # Filter imports that are still used
    new_imports=""
    while read -r import_line; do
        imported_class=$(echo "$import_line" | sed 's/^import \(.*\);\s*$/\1/' | awk -F'.' '{print $NF}')
        if echo "$used_classes" | grep -qw "$imported_class"; then
            new_imports+="$import_line"$'\n'
        else
            echo "Removing unused import: $import_line"
        fi
    done <<< "$imports"

    # Remove existing imports from the destination file
    sed -i '/^import /d' "$DEST_FILE"

    # Prepend the filtered imports to the destination file
    sed -i "1i$new_imports" "$DEST_FILE"
}

# Execute the appropriate operation
case "$OPERATION" in
    add)
        add_modules
        ;;
    remove)
        remove_modules
        ;;
    *)
        usage
        ;;
esac
