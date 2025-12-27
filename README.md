# MiniYAML

> ⚠️ **Experimental / Unstable (v0.1.0)**
>
> This is an early preview release.  
> Although most PyYAML features are implemented, the project has not yet  
> been extensively tested in real-world scenarios.  
>
> APIs and behavior may change without notice.  
> Bugs, edge cases, and incompatibilities are expected.  

MiniYAML is a GDScript port of [PyYAML](https://github.com/yaml/pyyaml), It also contains some code from [ruamel-yaml](https://yaml.dev/doc/ruamel.yaml/).  
"Mini" refers to both file size and structure; it's a single-script plugin.

And you can even use the underscore `_` in numbers!  
Just like you use in GDScript. AWEOSOME! 😎

I may have made quite a few mistakes during the porting process and didn't leave enough documentation.  
If you have any questions or find any bugs, you can open an issue and ask me directly.

Some of the document and examples in this repository were copied from [godot-yaml](https://github.com/fimbul-works/godot-yaml).  
If you want a more stable plugin, you should try it.

## Install
Requires godot **4.5** or higher.  
Porting it to an older version of godot is entirely possible, but I want to try out some new features while porting this plugin. So... that's it.

- You can use it simply by downloading the `addons.zip` file from the Releases page and then extracting it to your project folder.  
- Or, you can download this Git repository and copy the `addons` folder into your project.  
**Just remember to replace `soft_assert` with `assert` on line 130 of `miniyaml.gd`.**
- Or, you can directly download `addons/miniyaml/miniyaml.gd` to your project and then use it like an autoloaded singleton class.  
**Just remember to replace `soft_assert` with `assert` on line 130 of `miniyaml.gd`.**


## Quick Usage

```gdscript
# Parse YAML
var data = YAML.parse("key: value\nlist:\n  - item1\n  - item2").get_data()
# # Or, 
# var data = YAML.load("key: value\nlist:\n  - item1\n  - item2")
# # Or, For multiple documents
# var data = YAML.load_all("key: value\nlist:\n  - item1\n  - item2")

print(data.key)  # Outputs: value
print(data.list) # Outputs: [item1, item2]

# Generate YAML
var yaml_text = YAML.dump(data)
print(yaml_text)

# Working with Files
var file_data = YAML.load_file("res://doc/supported_syntax.yaml")
YAML.save_file(file_data, "user://dumped_supported_syntax.yaml")

# Custom class
YAML.register_class(MyCustomClass)
# # Or,
# YAML.register_class(MyCustomClass, "serialize", "deserialize")
YAML.unregister_class(MyCustomClass)
```
For more information, be sure to check out  
[BEFORE_YOU_START](./doc/BEFORE_YOU_START.md)  
[Custom class example](./doc/my_custom_class.gd)  
[Supported variable types](./doc/supported_syntax.yaml)  
[Dump Example](./doc/dumped_supported_syntax.yaml)  

## Known issues
- If you are still using `soft_assert` in your project, you might get stuck in a dangerous infinite loop when loading some faulty files.  
`soft_assert` is purely for testing purposes; you should use `assert`.  
Replace it in `miniyaml.gd` line **130**

- Some error report messages are very ugly.  
Yeah... because I really don't have the patience to copy error messages one-to-one.  
This will be fixed in the stable version.

- If you set the `allow_unicode` attribute of the `Emitter` to `false`, some strange spaces will be inserted into non-English strings.  
This is because the `write_indent()` method of the PyYAML `Emitter` is not perfect, which has been fixed in ruamel-yaml.  
However, the new implementation is a bit complicated, and I haven't had time to fix this issue yet.  
If you want to use non-English strings, don't change this setting.  

## Contributing
Pull requests from the community are welcome,  
But you should ensure that test results are improved or consistent with the old results.  
The output of the dump should be compared with `dumped_supported_syntax.yaml`.

And if you want to fix a bug, [ruamel-yaml](https://yaml.dev/doc/ruamel.yaml/) may have provided a solution; remember to check out its source code.

## Expected test failure
This plugin uses the official [YAML Test Suite](https://github.com/yaml/yaml-test-suite) for testing.

In the current version `0.1.0`, 

The event test (used to test the `Scanner` and `Parser`) results are [consistent with PyYAML](https://matrix.yaml.info/).  
Passed: **329**, Filed: **73**.

This test suite contains many strange edge cases, passing all tests is not the goal of this plugin.  
If you come across one of them, I'd be happy to help fix it.  
Otherwise, it's best to just leave them there.  

<br>

The result of the JSON test (used to test the `Composer`,`Resolver` and `Constructor`) is:  
Passed: **280**, Filed:**79**, Sipped:**14**, Ignored:**29**  

We ignored **29** tests because these tests did not provide the corresponding JSON files.  
(Some of these may be unable to provide JSON files because the test data is incorrect.)  
We skipped **14** tests because Godot's JSON parser does not accept the contents of the JSON files used in those tests.  

Of the **79** failed tests, 66 were due to event stream errors.  
Of the remaining 13 new errors,  
- `565N` failed because we converted the `binary` to `PackedByteArray`.  
- `S4JQ` and `3GZX` are due to errors that already existed in PyYAML.  
- The remaining 10 tests (`C4HZ`,`UGM3`,`CUP7`,`P76L`,`CC74`,`Z9M4`,`7FWL`,`6CK3`,`M5C3`,`Z67P`) all contain unknown tags; These tests should be considered errors for the `Constructor`.  

Oh, by the way, the error file indicator in YAML Test Suite only applies to event tests, not JSON tests.
