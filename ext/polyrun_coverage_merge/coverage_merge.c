#include <ruby.h>
#include <string.h>

static VALUE str_lines;
static VALUE str_branches;
static VALUE str_type;
static VALUE str_start_line;
static VALUE str_end_line;
static VALUE str_coverage;
static ID id_lines;
static ID id_branches;
static ID id_type;
static ID id_start_line;
static ID id_end_line;
static ID id_coverage;
static ID id_relevant;
static ID id_covered;
static ID id_sort_branches_for_native;

static VALUE
ignored_string(void)
{
    return rb_str_new_cstr("ignored");
}

static int
ignored_hit_p(VALUE value)
{
    if (!RB_TYPE_P(value, T_STRING)) {
        return 0;
    }

    return strcmp(StringValueCStr(value), "ignored") == 0;
}

static VALUE
line_hit_to_i(VALUE value)
{
    if (NIL_P(value)) {
        return Qnil;
    }
    if (RB_TYPE_P(value, T_FIXNUM) || RB_TYPE_P(value, T_BIGNUM)) {
        return value;
    }
    if (RB_TYPE_P(value, T_STRING)) {
        const char *text = StringValueCStr(value);
        char *end = NULL;
        long number = strtol(text, &end, 10);
        if (end != text && *end == '\0') {
            return LONG2FIX(number);
        }
        return Qnil;
    }
    if (RB_TYPE_P(value, T_SYMBOL)) {
        VALUE as_string = rb_sym2str(value);
        return line_hit_to_i(as_string);
    }

    return Qnil;
}

static int
line_hit_positive_p(VALUE value)
{
    VALUE as_int = line_hit_to_i(value);
    if (NIL_P(as_int)) {
        return 0;
    }

    VALUE comparison = rb_funcall(as_int, rb_intern(">"), 1, LONG2FIX(0));
    return RTEST(comparison);
}

static VALUE
coerce_line_array(VALUE value)
{
    if (NIL_P(value)) {
        return rb_ary_new();
    }
    if (!RB_TYPE_P(value, T_ARRAY)) {
        rb_raise(rb_eTypeError, "lines must be an Array");
    }

    return value;
}

static VALUE
line_array_for_count(VALUE value)
{
    if (NIL_P(value) || !RB_TYPE_P(value, T_ARRAY)) {
        return rb_ary_new();
    }

    return value;
}

static VALUE
merge_line_hits(VALUE left, VALUE right)
{
    if (NIL_P(left)) {
        return right;
    }
    if (NIL_P(right)) {
        return left;
    }
    if (ignored_hit_p(left) || ignored_hit_p(right)) {
        return ignored_string();
    }

    VALUE left_i = line_hit_to_i(left);
    VALUE right_i = line_hit_to_i(right);

    if (!NIL_P(left_i) && !NIL_P(right_i)) {
        return rb_funcall(left_i, rb_intern("+"), 1, right_i);
    }
    if (NIL_P(left_i) && !NIL_P(right_i)) {
        return right_i;
    }
    if (!NIL_P(left_i) && NIL_P(right_i)) {
        return left_i;
    }

    return left;
}

static VALUE
merge_line_arrays(VALUE left, VALUE right)
{
    left = coerce_line_array(left);
    right = coerce_line_array(right);

    long left_len = RARRAY_LEN(left);
    long right_len = RARRAY_LEN(right);
    long max_len = left_len > right_len ? left_len : right_len;
    VALUE out = rb_ary_new2(max_len);

    for (long index = 0; index < max_len; index++) {
        VALUE left_hit = index < left_len ? rb_ary_entry(left, index) : Qnil;
        VALUE right_hit = index < right_len ? rb_ary_entry(right, index) : Qnil;
        rb_ary_store(out, index, merge_line_hits(left_hit, right_hit));
    }

    return out;
}

static VALUE
hash_field(VALUE hash, VALUE string_key, ID symbol_key)
{
    VALUE value = rb_hash_aref(hash, string_key);
    if (NIL_P(value)) {
        value = rb_hash_aref(hash, ID2SYM(symbol_key));
    }

    return value;
}

static VALUE
branch_key(VALUE branch)
{
    if (!RB_TYPE_P(branch, T_HASH)) {
        branch = rb_hash_new();
    }

    return rb_ary_new3(
        3,
        hash_field(branch, str_type, id_type),
        hash_field(branch, str_start_line, id_start_line),
        hash_field(branch, str_end_line, id_end_line)
    );
}

static VALUE
coverage_count(VALUE branch)
{
    VALUE coverage = hash_field(branch, str_coverage, id_coverage);
    VALUE as_int = line_hit_to_i(coverage);
    if (NIL_P(as_int)) {
        return LONG2FIX(0);
    }

    return as_int;
}

static VALUE
merge_branch_entries(VALUE left, VALUE right)
{
    VALUE out = rb_hash_dup(left);
    VALUE sum = rb_funcall(coverage_count(left), rb_intern("+"), 1, coverage_count(right));
    rb_hash_aset(out, str_coverage, sum);

    return out;
}

static VALUE
merge_module_value(void)
{
    VALUE polyrun = rb_const_get(rb_cObject, rb_intern("Polyrun"));
    VALUE coverage = rb_const_get(polyrun, rb_intern("Coverage"));
    return rb_const_get(coverage, rb_intern("Merge"));
}

static VALUE
hash_keys(VALUE hash)
{
    return rb_funcall(hash, rb_intern("keys"), 0);
}

static VALUE
sort_branches(VALUE branches)
{
    if (!RB_TYPE_P(branches, T_ARRAY)) {
        return rb_ary_new();
    }
    if (RARRAY_LEN(branches) < 2) {
        return branches;
    }

    return rb_funcall(merge_module_value(), id_sort_branches_for_native, 1, branches);
}

static VALUE
duplicate_branch_side(VALUE value)
{
    if (NIL_P(value)) {
        return Qnil;
    }

    return rb_obj_dup(value);
}

static VALUE
coerce_branch_array(VALUE value)
{
    if (NIL_P(value)) {
        return Qnil;
    }
    if (!RB_TYPE_P(value, T_ARRAY)) {
        rb_raise(rb_eTypeError, "branches must be an Array");
    }

    return value;
}

static VALUE
merge_branch_arrays(VALUE left, VALUE right)
{
    if (NIL_P(left) && NIL_P(right)) {
        return Qnil;
    }
    if (NIL_P(left)) {
        return duplicate_branch_side(right);
    }
    if (NIL_P(right)) {
        return duplicate_branch_side(left);
    }

    left = coerce_branch_array(left);
    right = coerce_branch_array(right);

    VALUE index = rb_hash_new();
    VALUE sides[2] = {left, right};

    for (int side_index = 0; side_index < 2; side_index++) {
        VALUE array = sides[side_index];
        long length = RARRAY_LEN(array);

        for (long branch_index = 0; branch_index < length; branch_index++) {
            VALUE branch = rb_ary_entry(array, branch_index);
            if (!RB_TYPE_P(branch, T_HASH)) {
                continue;
            }

            VALUE key = branch_key(branch);
            VALUE existing = rb_hash_aref(index, key);
            VALUE merged = NIL_P(existing) ? rb_hash_dup(branch) : merge_branch_entries(existing, branch);
            rb_hash_aset(index, key, merged);
        }
    }

    VALUE values = rb_ary_new();
    VALUE branch_keys = hash_keys(index);
    long branch_count = RARRAY_LEN(branch_keys);
    for (long branch_index = 0; branch_index < branch_count; branch_index++) {
        VALUE key = rb_ary_entry(branch_keys, branch_index);
        rb_ary_push(values, rb_hash_aref(index, key));
    }

    return sort_branches(values);
}

static VALUE
normalize_file_entry(VALUE value)
{
    if (NIL_P(value)) {
        return Qnil;
    }
    if (RB_TYPE_P(value, T_ARRAY)) {
        VALUE entry = rb_hash_new();
        rb_hash_aset(entry, str_lines, value);
        return entry;
    }
    if (RB_TYPE_P(value, T_HASH)) {
        return value;
    }

    return Qnil;
}

static VALUE
entry_lines(VALUE entry)
{
    VALUE lines = rb_hash_aref(entry, str_lines);
    if (NIL_P(lines)) {
        lines = rb_hash_aref(entry, ID2SYM(id_lines));
    }

    return coerce_line_array(lines);
}

static VALUE
entry_lines_for_count(VALUE entry)
{
    VALUE lines = rb_hash_aref(entry, str_lines);
    if (NIL_P(lines)) {
        lines = rb_hash_aref(entry, ID2SYM(id_lines));
    }

    return line_array_for_count(lines);
}

static VALUE
entry_branches(VALUE entry)
{
    VALUE branches = rb_hash_aref(entry, str_branches);
    if (NIL_P(branches)) {
        branches = rb_hash_aref(entry, ID2SYM(id_branches));
    }

    return branches;
}

static VALUE
merge_file_entry(VALUE left, VALUE right)
{
    left = normalize_file_entry(left);
    right = normalize_file_entry(right);
    if (NIL_P(left)) {
        return right;
    }
    if (NIL_P(right)) {
        return left;
    }

    VALUE merged_lines = merge_line_arrays(entry_lines(left), entry_lines(right));
    VALUE entry = rb_hash_new();
    rb_hash_aset(entry, str_lines, merged_lines);

    VALUE left_branches = entry_branches(left);
    VALUE right_branches = entry_branches(right);
    if (!NIL_P(left_branches) || !NIL_P(right_branches)) {
        VALUE branches = merge_branch_arrays(left_branches, right_branches);
        if (!NIL_P(branches)) {
            rb_hash_aset(entry, str_branches, branches);
        }
    }

    return entry;
}

static VALUE
ensure_hash(VALUE value, const char *name)
{
    if (NIL_P(value)) {
        return rb_hash_new();
    }
    if (!RB_TYPE_P(value, T_HASH)) {
        rb_raise(rb_eTypeError, "%s must be a Hash", name);
    }

    return value;
}

static VALUE
merge_two(VALUE module, VALUE left, VALUE right)
{
    (void)module;

    left = ensure_hash(left, "left");
    right = ensure_hash(right, "right");

    VALUE primary = left;
    VALUE secondary = right;
    if (RHASH_SIZE(right) > RHASH_SIZE(left)) {
        primary = right;
        secondary = left;
    }

    VALUE out = rb_hash_new();
    VALUE primary_keys = hash_keys(primary);
    long primary_length = RARRAY_LEN(primary_keys);

    for (long index = 0; index < primary_length; index++) {
        VALUE key = rb_ary_entry(primary_keys, index);
        VALUE value = rb_hash_aref(primary, key);
        VALUE right_entry = rb_hash_aref(secondary, key);
        rb_hash_aset(out, key, merge_file_entry(value, right_entry));
    }

    VALUE secondary_keys = hash_keys(secondary);
    long secondary_length = RARRAY_LEN(secondary_keys);

    for (long index = 0; index < secondary_length; index++) {
        VALUE key = rb_ary_entry(secondary_keys, index);
        if (NIL_P(rb_hash_aref(out, key))) {
            rb_hash_aset(out, key, rb_hash_aref(secondary, key));
        }
    }

    return out;
}

static VALUE
line_counts(VALUE module, VALUE file_entry)
{
    (void)module;

    file_entry = normalize_file_entry(file_entry);
    long relevant = 0;
    long covered = 0;

    if (!NIL_P(file_entry)) {
        VALUE lines = entry_lines_for_count(file_entry);
        long length = RARRAY_LEN(lines);

        for (long index = 0; index < length; index++) {
            VALUE hit = rb_ary_entry(lines, index);
            if (NIL_P(hit) || ignored_hit_p(hit)) {
                continue;
            }

            relevant += 1;
            if (line_hit_positive_p(hit)) {
                covered += 1;
            }
        }
    }

    VALUE counts = rb_hash_new();
    rb_hash_aset(counts, ID2SYM(id_relevant), LONG2FIX(relevant));
    rb_hash_aset(counts, ID2SYM(id_covered), LONG2FIX(covered));

    return counts;
}

static VALUE
merge_line_arrays_method(VALUE module, VALUE left, VALUE right)
{
    (void)module;

    return merge_line_arrays(left, right);
}

void
Init_polyrun_coverage_merge(void)
{
    id_lines = rb_intern("lines");
    id_branches = rb_intern("branches");
    id_type = rb_intern("type");
    id_start_line = rb_intern("start_line");
    id_end_line = rb_intern("end_line");
    id_coverage = rb_intern("coverage");
    id_relevant = rb_intern("relevant");
    id_covered = rb_intern("covered");
    id_sort_branches_for_native = rb_intern("sort_branches_for_native");
    str_lines = rb_obj_freeze(rb_str_new_cstr("lines"));
    str_branches = rb_obj_freeze(rb_str_new_cstr("branches"));
    str_type = rb_obj_freeze(rb_str_new_cstr("type"));
    str_start_line = rb_obj_freeze(rb_str_new_cstr("start_line"));
    str_end_line = rb_obj_freeze(rb_str_new_cstr("end_line"));
    str_coverage = rb_obj_freeze(rb_str_new_cstr("coverage"));
    rb_global_variable(&str_lines);
    rb_global_variable(&str_branches);
    rb_global_variable(&str_type);
    rb_global_variable(&str_start_line);
    rb_global_variable(&str_end_line);
    rb_global_variable(&str_coverage);

    VALUE module = rb_define_module("PolyrunCoverageMerge");
    rb_define_singleton_method(module, "merge_line_arrays", merge_line_arrays_method, 2);
    rb_define_singleton_method(module, "merge_two", merge_two, 2);
    rb_define_singleton_method(module, "line_counts", line_counts, 1);
}
