#!/usr/bin/env python3
"""Dependency-free Xcode project generator. The shared build script is authoritative."""
from pathlib import Path
import hashlib
import json
root = Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quote(s): return json.dumps(str(s))
objects = {}
def put(name, body):
    key = ident(name)
    objects[key] = body
    return key
files = []
for folder in ['App', 'Helper', 'Shared', 'Sources', 'Tests', 'Resources', 'scripts']:
    children = []
    for path in sorted((root / folder).rglob('*')):
        if path.is_file():
            rel = str(path.relative_to(root))
            filetype = {'.swift':'sourcecode.swift','.plist':'text.plist.xml','.png':'image.png','.icns':'image.icns'}.get(path.suffix, 'text')
            children.append(put(rel, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;'))
    files.append(put('group-'+folder, f'isa = PBXGroup; children = ({",".join(children)}); name = {quote(folder)}; sourceTree = "<group>";'))
main = put('main', f'isa = PBXGroup; children = ({",".join(files)}); sourceTree = "<group>";')
def configs(name):
    ids = []
    for mode in ['Debug', 'Release']:
        ids.append(put(name+mode, f'isa = XCBuildConfiguration; buildSettings = {{ARCHS = arm64; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0;}}; name = {mode};'))
    return put(name+'configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(ids)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
targets = []
for name, script in [('IronZapper','build.sh'), ('Core Tests','test.sh')]:
    targets.append(put(name, f'isa = PBXLegacyTarget; buildArgumentsString = {quote("$(SRCROOT)/scripts/"+script)}; buildConfigurationList = {configs(name)}; buildPhases = (); buildToolPath = /bin/bash; buildWorkingDirectory = "$(SRCROOT)"; dependencies = (); name = {quote(name)}; passBuildSettingsInEnvironment = 1; productName = {quote(name)};'))
project = put('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {configs("project")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; projectDirPath = ""; projectRoot = ""; targets = ({",".join(targets)});')
path = root / 'IronZapper.xcodeproj'
path.mkdir(exist_ok=True)
(path / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {{{body}}};' for key,body in objects.items()) + f'\n}}; rootObject = {project}; }}\n')
scheme = path / 'xcshareddata/xcschemes'
scheme.mkdir(parents=True, exist_ok=True)
(scheme / 'IronZapper.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="IronZapper" BlueprintName="IronZapper" ReferencedContainer="container:IronZapper.xcodeproj"/></BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><PathRunnable runnableDebuggingMode="0" FilePath="$(PROJECT_DIR)/build/Iron Zapper.app"/></LaunchAction>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(path)
