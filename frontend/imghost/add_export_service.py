#!/usr/bin/env python3
import re
import uuid

# Read the project file
with open('ImageHost.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Generate UUIDs for the new file
file_ref_uuid = uuid.uuid4().hex[:24].upper()
build_file_uuid = uuid.uuid4().hex[:24].upper()

# Find the Services group and add the file reference
services_pattern = r'(/\* Services \*/ = \{[^}]+children = \([^)]+)'
services_match = re.search(services_pattern, content)
if not services_match:
    print("ERROR: Could not find Services group")
    exit(1)

# Add file reference to Services group children
services_replacement = services_match.group(1) + f'\n\t\t\t\t{file_ref_uuid} /* ExportService.swift */,'
content = content.replace(services_match.group(1), services_replacement)

# Find the PBXBuildFile section and add build file reference
build_file_section_pattern = r'(/\* Begin PBXBuildFile section \*/)'
build_file_match = re.search(build_file_section_pattern, content)
if build_file_match:
    build_file_entry = f'\n\t\t{build_file_uuid} /* ExportService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* ExportService.swift */; }};'
    content = content.replace(build_file_match.group(1), build_file_match.group(1) + build_file_entry)

# Find the PBXFileReference section and add file reference
file_ref_section_pattern = r'(/\* Begin PBXFileReference section \*/)'
file_ref_match = re.search(file_ref_section_pattern, content)
if file_ref_match:
    file_ref_entry = f'\n\t\t{file_ref_uuid} /* ExportService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ExportService.swift; sourceTree = "<group>"; }};'
    content = content.replace(file_ref_match.group(1), file_ref_match.group(1) + file_ref_entry)

# Find the PBXSourcesBuildPhase section and add to Sources
sources_phase_pattern = r'(/\* Sources \*/ = \{[^}]+files = \([^)]+)'
sources_match = re.search(sources_phase_pattern, content)
if sources_match:
    sources_replacement = sources_match.group(1) + f'\n\t\t\t\t{build_file_uuid} /* ExportService.swift in Sources */,'
    content = content.replace(sources_match.group(1), sources_replacement)

# Write the modified content back
with open('ImageHost.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print(f"Added ExportService.swift to Xcode project")
print(f"File Reference UUID: {file_ref_uuid}")
print(f"Build File UUID: {build_file_uuid}")
