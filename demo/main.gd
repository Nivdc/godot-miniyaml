extends Control

var test_array :Array[Test]
var parser :Object

func _ready():
    $%ReloadPluginButton.pressed.connect(reload_plugin)
    reload_test_files()
    reload_plugin()

    # print("abcd".to_utf8_buffer())

    # print("\u0000" == "\u0000")
    # exec_texts()
    var yaml_string = """
- a
- b
- c
"""

    print(yaml_string.split())
    parser.parse(yaml_string)
    

func reload_test_files():
    var test_file_dir_path = "res://test_data/yaml-test-suite-data-2022-01-17"
    var dir = DirAccess.open(test_file_dir_path)

    for dir_name in dir.get_directories():
        if dir_name in ["name", "tags"]: # Ignore these two metadata directories
            continue

        var sub_dir_path = test_file_dir_path + "/%s" % dir_name
        if DirAccess.get_directories_at(sub_dir_path).size() == 0:
            test_array.append(Test.new(sub_dir_path))
        else:
            for sub_test_number in DirAccess.get_directories_at(sub_dir_path):
                var sub_sub_dir_path = sub_dir_path + "/%s" % sub_test_number
                test_array.append(Test.new(sub_sub_dir_path))
        
        break


    $%TestFileTree.clear()
    $%TestFileTree.set_column_title(0, "ID")
    $%TestFileTree.set_column_title(1, "Name")
    $%TestFileTree.set_column_title(2, "Status")
    $%TestFileTree.set_column_expand_ratio(1,4)

    # $%TestFileTree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
    # $%TestFileTree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
    # $%TestFileTree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)

    var test_file_tree_root = $%TestFileTree.create_item()
    for test in test_array:
        var test_treeitem = $%TestFileTree.create_item(test_file_tree_root)
        test_treeitem.set_text(0, test.id)
        test_treeitem.set_text(1, test.name)
        test_treeitem.set_text(2, test.status)

func reload_plugin():
    parser = load("res://addons/sgyp/sgyp.gd").new()

func exec_texts():
    for t in test_array:
        t.exec(parser)

class Test:
    var id :String
    var name :String # Title/Label
    static var valid_status :Array[String] = ["Pending", "Success", "Failed"]
    var status :String = "Pending" :
        set(value):
            assert(value in valid_status, "Invalid Test status.")
            status = value

    var _file_path :String
    var _in_yaml :String
    var _test_event :String
    var _in_json :String
    var _out_yaml :String
    var _should_be_error :bool = false
    var _emit_yaml :String

    func _init(p_file_path:String):
        var regex = RegEx.create_from_string(r"^res://.+/(?<id>\w{4}(?:/\d{2,3})?)$")
        var result= regex.search(p_file_path)

        assert(result != null)
        id         = result.get_string("id")
        assert(FileAccess.file_exists(p_file_path + "/==="))
        name = FileAccess.open(p_file_path + "/===", FileAccess.READ).get_as_text()

        _file_path = p_file_path
        assert(FileAccess.file_exists(p_file_path + "/in.yaml"))
        _in_yaml = FileAccess.open(p_file_path + "/in.yaml", FileAccess.READ).get_as_text()

        if FileAccess.file_exists(p_file_path + "/test.event"):
            _test_event = FileAccess.open(p_file_path + "/test.event", FileAccess.READ).get_as_text()

        if FileAccess.file_exists(p_file_path + "/in.json"):
            _in_json = FileAccess.open(p_file_path + "/in.json", FileAccess.READ).get_as_text()
 
        if FileAccess.file_exists(p_file_path + "/out.yaml"):
            _out_yaml = FileAccess.open(p_file_path + "/out.yaml", FileAccess.READ).get_as_text()

        if FileAccess.file_exists(p_file_path + "/error"):
            _should_be_error = true

        if FileAccess.file_exists(p_file_path + "/emit.yaml"):
            _emit_yaml = FileAccess.open(p_file_path + "/emit.yaml", FileAccess.READ).get_as_text()

    func exec(parser :Object):
        var input_bytes :PackedByteArray = FileAccess.get_file_as_bytes(_file_path + "/in.yaml")
        parser.parse(input_bytes)
