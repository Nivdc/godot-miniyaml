extends Control

var test_array :Array[Test]
var tag_dic :Dictionary

var parser :Object

func _ready():
    $%ReloadPluginButton.pressed.connect(reload_plugin)
    reload_test_files()
    reload_plugin()
    exec_tests()

    # var yaml_string = """能够全年不间断的生产农作物。在缺少肥料时也能生产，但产量会降低。"""
    # var yaml_string = """asdfsfsfdsfsfsfsfdfadfadfdfxvcasdasdadasdadasdafasfasfasfsaf"""
#     var yaml_string = 'foo:
#   bar
# invalid
# '
#     print(parser.parse_to_events(yaml_string))
    # parser.parse(yaml_string)
    # print(parser.dump(parser.parse(yaml_string)))
    # # print(parser.parse(parser.dump(parser.parse(yaml_string))))
    # print(parser.dump(yaml_string))
    # print(parser.dump(yaml_string))
#     print(parser.parse("---
# seq:
#  &anchor
# - a
# - b
# "))

# const skip_test_list = [
#     "2JQS", 
#     # check https://github.com/yaml/yaml-test-suite/issues/25 
#     # and https://github.com/yaml/yaml-test-suite/pull/40
# ]

const skip_tag = [
    "empty-key",
]

func reload_test_files():
    var test_file_dir_path = "res://test_data/yaml-test-suite-data-2022-01-17"
    var tag_dir_path = test_file_dir_path+"/tags"
    for tag_name in DirAccess.get_directories_at(tag_dir_path):
        tag_dic[tag_name] = []
        for test_id in DirAccess.get_files_at(tag_dir_path+"/"+tag_name):
            tag_dic[tag_name].append(test_id)
        for group_test_id in DirAccess.get_directories_at(tag_dir_path+"/"+tag_name):
            for sub_test_number in DirAccess.get_directories_at(tag_dir_path+"/"+tag_name+"/"+group_test_id):
                var test_id = group_test_id+"/"+sub_test_number
                tag_dic[tag_name].append(test_id)

    for dir_name in DirAccess.get_directories_at(test_file_dir_path):
        if dir_name not in ["name", "tags"]: # Ignore these two metadata directories
            var sub_dir_path = test_file_dir_path + "/" + dir_name
            if DirAccess.get_directories_at(sub_dir_path).size() == 0:
                test_array.append(Test.new(sub_dir_path, tag_dic))
            else:
                for sub_test_number in DirAccess.get_directories_at(sub_dir_path):
                    var sub_sub_dir_path = sub_dir_path + "/%s" % sub_test_number
                    test_array.append(Test.new(sub_sub_dir_path, tag_dic))

        # break


    $%TestFileTree.clear()
    $%TestFileTree.set_column_title(0, "ID")
    $%TestFileTree.set_column_title(1, "Name")
    $%TestFileTree.set_column_title(2, "Status")
    $%TestFileTree.set_column_expand_ratio(1,4)

    $%TotalNumberLabel.text = "Total number of tests: %d" % test_array.size()

    # $%TestFileTree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
    # $%TestFileTree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
    # $%TestFileTree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)

func reload_plugin():
    parser = load("res://addons/sgyp/sgyp.gd").new()

func exec_tests():
    var test_file_tree_root = $%TestFileTree.create_item()

    test_array.sort_custom(func(a, b): return a.name < b.name)
    # test_array = test_array.filter(func(t): return t._should_be_error)
    for test in test_array:
        var test_treeitem = $%TestFileTree.create_item(test_file_tree_root)
        if test.tags.all(func(tag): return tag not in skip_tag):
            # if test.id == "4EJS":
                test.exec(parser)
        else:
            test.status = "Skipped"

        test_treeitem.set_text(0, test.id)
        test_treeitem.set_text(1, test.name)
        test_treeitem.set_text(2, test.status)
        var color = Color.GREEN if test.status == "Passed" else Color.RED
        test_treeitem.set_custom_color(2, color)

        if test.status == "Skipped":
            test_treeitem.set_custom_color(2, Color.YELLOW)

        if test.status == "Pending":
            test_treeitem.set_custom_color(2, Color.GRAY)


        # if test.status == "Failed":
        #     break

    $%FailedLabel.text = "Failed: [color=red]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.status == "Failed" else count, 0)
    $%PassedLabel.text = "Passed: [color=green]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.status == "Passed" else count, 0)
    $%SkippedLabel.text = "Skipped: [color=yellow]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.status == "Skipped" else count, 0)


class Test:
    var id :String
    var name :String # Title/Label
    var tags :Array[String]
    static var valid_status :Array[String] = ["Pending", "Passed", "Failed"]
    var status :String = "Pending"

    var _file_path :String
    var _in_yaml :String
    var _test_event :String
    var _in_json :String
    var _out_yaml :String
    var _should_be_error :bool = false
    var _emit_yaml :String

    func _init(p_file_path:String, tag_dic:Dictionary):
        var regex = RegEx.create_from_string(r"^res://.+/(?<id>\w{4}(?:/\d{2,3})?)$")
        var result= regex.search(p_file_path)

        assert(result != null)
        id = result.get_string("id")
        assert(FileAccess.file_exists(p_file_path + "/==="))
        name = FileAccess.open(p_file_path + "/===", FileAccess.READ).get_as_text()

        for tag in tag_dic:
            if id in tag_dic[tag]:
                tags.append(tag)

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
        # var input_bytes :PackedByteArray = FileAccess.get_file_as_bytes(_file_path + "/in.yaml")
        # print(input_bytes)
        # var result = parser.parse(input_bytes)
        # print(result)
        # print(_test_event)
        # print(parser.parse_to_events(_in_yaml))
        # print(parser.parse_to_events(_in_yaml) == _test_event)

        var result_events = parser.parse_to_events(_in_yaml)

        if result_events == _test_event:
            status = "Passed"
        else:
            # print(result_events)
            if _should_be_error and parser.has_error():
                status = "Passed"
            else:
                status = "Failed"


        # ridiculous Godot
        # print(type_string(typeof(result[0].hr)))
        # print(type_string(typeof(JSON.parse_string(_in_json)[0].hr)))
        # print(JSON.stringify(JSON.parse_string(_in_json)))
        # print(JSON.stringify(JSON.parse_string(JSON.stringify(result))))
        # print(JSON.stringify(65))
        # print(JSON.stringify(JSON.parse_string(JSON.stringify(65))))
