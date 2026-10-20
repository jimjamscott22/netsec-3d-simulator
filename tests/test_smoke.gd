class_name TestSmoke
extends GdUnitTestSuite


func test_framework_runs() -> void:
	assert_int(1 + 1).is_equal(2)
