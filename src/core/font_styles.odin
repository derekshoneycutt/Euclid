package core

//   Return canonical weight ordering rank for heaviest-flag resolution.
font_weight_rank :: #force_inline proc(weight: Font_Weight) -> int {
	switch weight {
	case .Light:
		return 1
	case .Regular:
		return 2
	case .Medium:
		return 3
	case .SemiBold:
		return 4
	case .Bold:
		return 5
	case .ExtraBold:
		return 6
	case .Black:
		return 7
	}

	return 2
}

//   Return true when one requested variant-flag bit is present.
font_has_flag :: #force_inline proc(flags, flag: Font_Variant_Flags) -> bool {
	return (u32(flags) & u32(flag)) != 0
}

//   Resolve one weight from possibly multiple weight bits by choosing the heaviest bit set.
font_resolve_weight_from_flags :: #force_inline proc(
	flags: Font_Variant_Flags) -> Font_Weight {
	resolved := Font_Weight.Regular
	resolved_rank := font_weight_rank(resolved)

	if font_has_flag(flags, .Light) {
		rank := font_weight_rank(.Light)
		if rank > resolved_rank {
			resolved = .Light
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Regular) {
		rank := font_weight_rank(.Regular)
		if rank > resolved_rank {
			resolved = .Regular
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Medium) {
		rank := font_weight_rank(.Medium)
		if rank > resolved_rank {
			resolved = .Medium
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .SemiBold) {
		rank := font_weight_rank(.SemiBold)
		if rank > resolved_rank {
			resolved = .SemiBold
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Bold) {
		rank := font_weight_rank(.Bold)
		if rank > resolved_rank {
			resolved = .Bold
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .ExtraBold) {
		rank := font_weight_rank(.ExtraBold)
		if rank > resolved_rank {
			resolved = .ExtraBold
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Black) {
		rank := font_weight_rank(.Black)
		if rank > resolved_rank {
			resolved = .Black
			resolved_rank = rank
		}
	}

	return resolved
}
