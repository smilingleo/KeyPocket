from pathlib import Path
import plistlib, json, shutil
root=Path(__file__).resolve().parents[1]
p=root/'KeyPocket.xcodeproj/project.pbxproj'
s=p.read_text()
if 'KeyPocketWatch.app' in s: raise SystemExit('Watch target already exists')
def uid(i):return f'{0x1000+i:024X}'
objects=[]
def obj(i,body): objects.append(f'{uid(i)} = {{ {body} }};')
def ids(*items):return ', '.join(uid(i) for i in items)+','
# Root-relative shared files.
for i,path in [(1,'Shared/WatchBridge.swift'),(2,'KeyPocketWatch/WatchApp.swift'),(3,'KeyPocketWatch/WatchSoundClient.swift')]:
 obj(i,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = SOURCE_ROOT;')
obj(4,'isa = PBXFileReference; explicitFileType = wrapper.application; path = KeyPocketWatch.app; sourceTree = BUILT_PRODUCTS_DIR;')
for i,file in [(10,1),(11,1),(12,2),(13,3)]:obj(i,f'isa = PBXBuildFile; fileRef = {uid(file)};')
for i,ref in [(14,'000000000000000000000066'),(15,'000000000000000000000067'),(16,'00000000000000000000006B')]:obj(i,f'isa = PBXBuildFile; fileRef = {ref};')
obj(17,'isa = PBXBuildFile; productRef = '+uid(30)+';')
obj(18,f'isa = PBXBuildFile; fileRef = {uid(4)}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
obj(20,f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ids(11,12,13,14,15)}); runOnlyForDeploymentPostprocessing = 0;')
obj(21,f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ids(17)}); runOnlyForDeploymentPostprocessing = 0;')
obj(22,f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ids(16,41)}); runOnlyForDeploymentPostprocessing = 0;')
obj(23,f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = ({ids(18)}); name = "Embed Watch Content"; runOnlyForDeploymentPostprocessing = 0;')
obj(24,f'isa = PBXContainerItemProxy; containerPortal = 000000000000000000000001; proxyType = 1; remoteGlobalIDString = {uid(29)}; remoteInfo = KeyPocketWatch;')
obj(25,f'isa = PBXTargetDependency; target = {uid(29)}; targetProxy = {uid(24)};')
obj(26,f'isa = XCConfigurationList; buildConfigurations = ({ids(27,28)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
for i,name in [(27,'Debug'),(28,'Release')]:
 obj(i,f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
 SDKROOT = watchos; SUPPORTED_PLATFORMS = "watchos watchsimulator"; WATCHOS_DEPLOYMENT_TARGET = 11.0;
 TARGETED_DEVICE_FAMILY = 4; SWIFT_VERSION = 5.0; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = TLAMM3823Y;
 PRODUCT_BUNDLE_IDENTIFIER = net.smilingleo.KeyPocket.watchkitapp; PRODUCT_NAME = "$(TARGET_NAME)";
 GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = KeyPocketWatch/Info.plist; SKIP_INSTALL = YES;
 CURRENT_PROJECT_VERSION = 6; MARKETING_VERSION = 1.4; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
 SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{'DEBUG' if name=='Debug' else ''}";
 }};''')
obj(29,f'''isa = PBXNativeTarget; buildConfigurationList = {uid(26)}; buildPhases = ({ids(20,21,22)}); buildRules = (); dependencies = ();
 name = KeyPocketWatch; productName = KeyPocketWatch; productReference = {uid(4)}; productType = "com.apple.product-type.application"; packageProductDependencies = ({ids(30)});''')
obj(30,'isa = XCSwiftPackageProductDependency; package = 000000000000000000000010; productName = KeyPocketCore;')
obj(40,'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = KeyPocketWatch/Assets.xcassets; sourceTree = SOURCE_ROOT;')
obj(41,f'isa = PBXBuildFile; fileRef = {uid(40)};')
s=s.replace('objects = {','objects = {\n'+'\n'.join(objects),1)
s=s.replace('000000000000000000000003 /* KeyPocket */,',f'{ids(1,2,3,40)}\n000000000000000000000003 /* KeyPocket */,',1)
s=s.replace('000000000000000000000006 /* KeyPocket.app */,',f'{ids(4)}\n000000000000000000000006 /* KeyPocket.app */,',1)
s=s.replace('000000000000000000000009 /* Resources */,',f'000000000000000000000009 /* Resources */,\n{ids(23)}',1)
s=s.replace('dependencies = (\n\t\t\t);',f'dependencies = ({ids(25)});',1)
s=s.replace('targets = (','targets = (\n'+ids(29),1)
s=s.replace('files = (\n\t\t\t\t0000000000000000000000CD,','files = (\n'+ids(10)+'\n\t\t\t\t0000000000000000000000CD,',1)
s=s.replace('HXCD5XXP64','TLAMM3823Y').replace('local.keypocket.iphone','net.smilingleo.KeyPocket').replace('CURRENT_PROJECT_VERSION = 5','CURRENT_PROJECT_VERSION = 6').replace('MARKETING_VERSION = 1.3','MARKETING_VERSION = 1.4')
p.write_text(s)
p=root/'Configuration/AppStore.xcconfig';p.write_text('\n'.join(x for x in p.read_text().splitlines() if not x.startswith('PRODUCT_BUNDLE_IDENTIFIER'))+'\n')
p=root/'KeyPocket/Info.plist';d=plistlib.loads(p.read_bytes());d['CFBundleShortVersionString']='1.4';d['CFBundleVersion']='6';p.write_bytes(plistlib.dumps(d))
w={k:d[k] for k in ['CFBundleDisplayName','CFBundleExecutable','CFBundleIdentifier','CFBundleName','CFBundlePackageType','CFBundleShortVersionString','CFBundleVersion','NSAppTransportSecurity','NSBluetoothAlwaysUsageDescription']}
w.update(WKApplication=True,WKCompanionAppBundleIdentifier='net.smilingleo.KeyPocket',WKRunsIndependentlyOfCompanionApp=True)
(root/'KeyPocketWatch/Info.plist').write_bytes(plistlib.dumps(w))
asset=root/'KeyPocketWatch/Assets.xcassets/AppIcon.appiconset';asset.mkdir(parents=True,exist_ok=True)
src=root/'KeyPocket/Assets.xcassets/AppIcon.appiconset/Icon-1024@1x.png';shutil.copy(src,asset/'AppIcon.png')
(asset/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'watchos','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
scheme=(root/'KeyPocket.xcodeproj/xcshareddata/xcschemes/KeyPocket.xcscheme').read_text().replace('000000000000000000000005',uid(29)).replace('KeyPocket.app','KeyPocketWatch.app').replace('BlueprintName = "KeyPocket"','BlueprintName = "KeyPocketWatch"')
(root/'KeyPocket.xcodeproj/xcshareddata/xcschemes/KeyPocketWatch.xcscheme').write_text(scheme)
