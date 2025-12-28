class_name MyCustomClass extends Node

var self_ref:MyCustomClass
@export var alias: String
@export var health: int
@export var color: Color

# Your custom class MUST have an initialization function, 
# and the parameters of the initialization function MUST have default values.
# In other words, your custom class MUST be able to construct an empty object.
# This is to solve the problem of self-references.

# By default, the parser expects your parameters to begin with 'p_' , 
# and the data to be assigned to a property with the same name (after removing 'p_').

# If you do this, you won't need to write any extra functions.
# If not, then you need to register your custom serialize and deserialize.
func _init(p_alias := "", p_health := 0, p_color := Color()) -> void:
    alias  = p_alias
    health = p_health
    color  = p_color

func hello():
    print(alias)


# # The names of the `serialize` and `deserialize` methods can be customized.
# # but I personally recommend using 'to_dict' and '_from_dict'. 
# # This way, 'from_dict' can be reserved for your static function.
# 
# # The parser expects your serialize to return a Dictionary.

# func to_dict() -> Dictionary:
#     return {
#         "self_ref": self,
#         "alias": alias,
#         "health": health,
#         "color": color,
#     }

# # Your deserialize function will get a dictionary of objects constructed from the text data,
# # Then you can do whatever you want.
# 
# # Note that deserialize function can NOT be static, and it does not require a return value.
# # This is also due to the self-reference problem.

# func _from_dict(data: Dictionary):
#     self_ref = data.self_ref
#     alias    = data.alias
#     health   = data.health
#     color    = data.color

func _to_string() -> String:
    return "MyCustomClass(%s %s %s)" % [alias, health, color] 
