#!/usr/bin/env python3
"""
Script to integrate xcconfig files into Xcode project.
Adds Config/Debug.xcconfig and Config/Release.xcconfig to the project
and assigns them to the respective build configurations.
"""

import re
import sys

def main():
    project_path = "/Users/codybontecou/dev/ios-share/frontend/ImageHost/ImageHost.xcodeproj/project.pbxproj"

    with open(project_path, 'r') as f:
        content = f.read()

    # Generate unique IDs for the xcconfig files
    debug_xcconfig_ref = "A10000F1000"
    release_xcconfig_ref = "A10000F2000"
    config_group_ref = "A10000F3000"

    # Step 1: Add file references for xcconfig files
    file_ref_section = re.search(r'/\* Begin PBXFileReference section \*/(.*?)/\* End PBXFileReference section \*/', content, re.DOTALL)
    if file_ref_section:
        file_refs = file_ref_section.group(1)

        # Check if xcconfig files are already referenced
        if 'Debug.xcconfig' not in file_refs:
            # Add before the closing comment
            new_refs = f"\t\t{debug_xcconfig_ref} /* Debug.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = \"<group>\"; }};\n"
            new_refs += f"\t\t{release_xcconfig_ref} /* Release.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = \"<group>\"; }};\n"

            content = content.replace(
                '/* End PBXFileReference section */',
                new_refs + '/* End PBXFileReference section */'
            )

    # Step 2: Add Config group to PBXGroup section
    group_section = re.search(r'/\* Begin PBXGroup section \*/(.*?)/\* End PBXGroup section \*/', content, re.DOTALL)
    if group_section:
        groups = group_section.group(1)

        # Check if Config group exists
        if config_group_ref not in groups:
            # Add Config group
            config_group = f"\t\t{config_group_ref} /* Config */ = {{\n"
            config_group += "\t\t\tisa = PBXGroup;\n"
            config_group += "\t\t\tchildren = (\n"
            config_group += f"\t\t\t\t{debug_xcconfig_ref} /* Debug.xcconfig */,\n"
            config_group += f"\t\t\t\t{release_xcconfig_ref} /* Release.xcconfig */,\n"
            config_group += "\t\t\t);\n"
            config_group += "\t\t\tpath = Config;\n"
            config_group += "\t\t\tsourceTree = \"<group>\";\n"
            config_group += "\t\t};\n"

            # Add before End PBXGroup section
            content = content.replace(
                '/* End PBXGroup section */',
                config_group + '/* End PBXGroup section */'
            )

            # Add Config group to the root group (A10000A0000)
            # Find and update the root group's children array
            root_group_pattern = r'(A10000A0000 = \{\s*isa = PBXGroup;\s*children = \(\s*)'
            replacement = rf'\1{config_group_ref} /* Config */,\n\t\t\t\t'
            content = re.sub(root_group_pattern, replacement, content)

    # Step 3: Assign xcconfig files to build configurations
    # Update Debug configuration for project
    debug_config_pattern = r'(A1000180000 /\* Debug \*/ = \{\s*isa = XCBuildConfiguration;)'
    content = re.sub(
        debug_config_pattern,
        rf'\1\n\t\t\tbaseConfigurationReference = {debug_xcconfig_ref} /* Debug.xcconfig */;',
        content
    )

    # Update Release configuration for project
    release_config_pattern = r'(A1000190000 /\* Release \*/ = \{\s*isa = XCBuildConfiguration;)'
    content = re.sub(
        release_config_pattern,
        rf'\1\n\t\t\tbaseConfigurationReference = {release_xcconfig_ref} /* Release.xcconfig */;',
        content
    )

    # Write back to file
    with open(project_path, 'w') as f:
        f.write(content)

    print("Successfully integrated xcconfig files into Xcode project!")
    print(f"- Added {debug_xcconfig_ref} for Debug.xcconfig")
    print(f"- Added {release_xcconfig_ref} for Release.xcconfig")
    print(f"- Created Config group {config_group_ref}")
    print("- Assigned xcconfig files to Debug and Release configurations")

if __name__ == "__main__":
    main()
