# Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
extends SkeletonModifier3D

var edits: Control

func _process_modification_with_delta(_delta: float) -> void:
	if is_instance_valid(edits):
		edits.apply_pose(get_skeleton())
