![Creación_de_Adán_(Miguel_Ángel)_modified_version](./Creación_de_Adán_(Miguel_Ángel)_modified_version.jpg)

> The Prophet cries out:  
> Behold — behold!  
> **YAML**, the god of data serialization, has descended upon this world,  
> and shall lead us to ascend into Its kingdom!  

> I believe YAML is the ultimate answer to serialization and deserialization —  
> or at least, it comes very close.  

## What Is YAML？

You can find countless excellent YAML tutorials online.  
Syntax references.  
Structure diagrams.  
Comparisons with JSON.

All of that exists — and all of that is useful.

But I believe none of it captures what YAML is *really* about.

So instead, let me ask you to imagine something.

<br>

Imagine you are programming in your favorite object-oriented language.

You want to model something from the real world, so you begin to write a class.  
Let’s choose something simple: a `Person`.

You give it a `name`.  
You give it an `age`.  
Then you are about to write a method — `hello_world()`...

Wait.

Don’t write the method yet.

Delete `hello_world()`.  
Keep only the data.

Now look at what remains.

Does it look ...

```yaml
!Person
name: Alice
age: 18
```
... suspiciously like this?

**You thought you were *only* writing your favorite language.  
You were also writing YAML.**

## What Exists in Its Kingdom?
I cannot remember how many times I have written code just to unpack JSON.

Assigning fields one by one.  
Writing loaders.  
Mapping dictionaries into objects.  
Or wrapping raw data with clever proxies.  

If this were JSON, it would probably look like this:
```json
{
  "name": "Alice",
  "age": 18
}
```
So what do you do with this JSON?

You load it.  
You unpack it.  
You assign its fields one by one.  

Somewhere, in your code, you must say:  

“This data… is a Person.”  

The data itself never tells you that.  
It is silent.  
It is anonymous.  


```json
{
  "name": "Alice",
  "age": 18
}
```

This could be a Person.  
It could be an Enemy.  
It could be a SaveFile.  
The structure alone does not know.  

So you write glue code.  
Loaders.  
Mappers.  
Adapters.  
Endless `from_json` functions...  

<br>

And then YAML quietly asks a different question:

What if the data could speak for itself?  
What if the data could say what it *is*?  

```yaml
!Person
name: Alice
age: 18
```

This is not just data anymore.  
This is identity.  

YAML does not force meaning upon your data.  
It allows your data to declare its own meaning.  

**Everything can be described as data.  
All data has meaning.  
YAML makes it visible.**

## How Do We Reach Its Kingdom?

Now, let us look at how YAML data is used.

```yaml
!Person
name: Alice
age: 18
```

Suppose there is no parser yet,  
and you must write one yourself.  

How would you do it?

<br>

Have you realized that—  
because the data declares its own identity,  
you can recognize its type during construction,  
and *reflectively* populate an object with it?  

**YES!**  
That is exactly how it works.

```gdscript
class Person:
    var name
    var age

    func _init(p_name, p_age):
        name = p_name
        age = p_age

    func say_hello_to_every_one():
        print("hello")
```

```gdscript
    YAML.register_class(Person)
    var person :Person = YAML.load("""

    !Person
    name: Alice
    age: 18

    """)

    person.say_hello_to_every_one() # output: hello
```

<br>

**THIS IS IT'S KINGDOM.  
ITS KINGDOM HAS COME.** 

## Epilogue
I do not wish to deceive anyone.

The world I have glimpsed is so beautiful  
that I do not believe it reveals itself without a cost.  

Because the constructions YAML enables are so powerful,  
it is **EASY** to leave security vulnerabilities in deserialization code.  
There will always be YAML input you did not expect —  
and those surprises may break your assumptions, or your system.

Therefore:  
Do **NOT** load typed YAML from untrusted sources.  
Do not apply the type system everywhere without restraint.

Master it.  
Do not let it master you.

<br>

And there is also the matter of performance.

I have not performed stress tests yet,  
but there is reason to suspect that, in practice,  
we may not be able to support extremely large-scale typed data processing.

And yet, I also believe this limitation will one day be overcome.  
When that happens, everything will be different.  

> To those who have read this far:  
> I know you cannot go back now.  
> You can no longer return to a world without **YAML**.  
