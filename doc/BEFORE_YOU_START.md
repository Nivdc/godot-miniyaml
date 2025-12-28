There are a few issues you should pay special attention to before you start using MiniYAML.

## Input and output differences
It's easy to mistakenly assume that YAML data can be output exactly as it was input.

However, the output data will always have some subtle differences from the input data, and these differences may cause errors.  
You should take some time to compare the [input](supported_syntax.yaml) and [output](dumped_supported_syntax.yaml) files to make sure you fully understand the differences.  

We will only point out a few key differences here:
1. The precision of `float` numbers within certain variables will change.  
    For example:
    ```yaml
    Quaternion: !Quaternion {x: 3.1415927,y: 6.2831855,z: 12.566371,w: 25.132742}
    ```
    will dump:
    ```yaml
    Quaternion: !Quaternion {x: 3.14159274101257, y: 6.28318548202515, z: 12.5663709640503,  w: 25.1327419281006}
    ```
    This is a strange behavior of the engine; in fact, if you test the following code:  
    ```gdscript
    var f = 3.1415927
    var q = Quaternion(f,f,f,f)
    print(f)    # Output: 3.1415927
    print(q.x)  # Output: 3.14159274101257
    print(f == q.x)  # Output: false
    print(is_equal_approx(f, q.x)) # Output: true
    ```
    I haven't found a way to fix this issue yet, but I have noticed that [godot-yaml](https://github.com/fimbul-works/godot-yaml) has better precision control.  
    If you really need high precision, you can try that plugin.
    
    Note that this issue can also reduce `float` precision in some cases.  
    Be sure to review the output examples of **PackedFloat64Array** and **PackedFloat32Array** to ensure the format meets your expectations.

3. `Timestamps` will dump as `String`  
    For example:
    ```yaml
    date: 2002-12-14
    ```
    will dump:
    ```yaml
    date: '2002-12-14'
    ```
    Because Godot does not provide a type to represent timestamps, timestamps can only be parsed as strings.  
    However, during the output process, the `Serializer` will find a string that conforms to the timestamp format.  
    In order to prevent this string from being "mistakenly identified" as a timestamp, it will actively mark this distinction.
    
    What we ultimately see is a string enclosed in single quotes.  
    This usually doesn't cause any problems unless you intend to submit the output YAML to another parser, in which case the timestamp will be lost after conversion.  

5. The `Array` will be output in a compact format  
    For example:
    ```yaml
    fruits:
      - apple
      - banana
      - cherry
    ```
    will dump:
    ```yaml
    fruits:
    - apple
    - banana
    - cherry
    ```
    Both formats are valid and can be parsed correctly, so I tend to retain the behavior of PyYAML.  
    If you really dislike this output format, you can set `indentless` to `false` in `func expect_block_sequence()`. Then the output will be more normal.  

## Unstable anchor for Array/Dictionary
Suppose you have the following YAML file:
```yaml
inventory: &inventory
  - AK47
  - MagicBook
partner_1:
  team_inventory: *inventory
partner_2:
  team_inventory: *inventory
```
When you first load the data, everything seems to work fine.
`partner_1` and `partner_2` do indeed share the same inventory.

However, once you want to save the data, it will be saved as...
```yaml
inventory:
- AK47
- MagicBook
partner_1:
  team_inventory:
  - AK47
  - MagicBook
partner_2:
  team_inventory:
  - AK47
  - MagicBook
```

Did you notice anything different?   
`team_inventory` has become two completely different arrays.  
When you reload the data, they will NOT be the same array.  

#### Why did this happen?
While GDScript does pass Array/Dictionary by reference, but I haven't been able to find a way to determine if two arrays (or dictionaries) come from the same reference.  
If you have a way, please let me know.  

#### How to fix it?
Be careful to avoid this situation; if necessary, use a custom class to wrap the array and dictionary.  
MiniYAML can correctly handle object references.  


## Self-referencing problem
Suppose you have the following YAML file:
```yaml
world: &world
  player:  
    world: *world
```
Now, let's try to construct world.   
By definition, we should construct player.  
Okay, let's construct player.  
Oops, to construct player, we must first construct world.  
What should we do?  

#### How to fix it?
The YAML specification allows self-references, and MiniYAML can perfectly handle self-references in arrays and dictionaries.

However, when using custom classes, you must ensure that your custom class can construct an empty object;  
In other words, the parameters of your `_init` function must have default values.  

<br>

And, you can avoid using this circular reference design.  

Whenever the `player`'s data needs to cause some change in the `world`, it can send a **signal**, and then the `world` can connect to the corresponding handler function for that **signal**.
