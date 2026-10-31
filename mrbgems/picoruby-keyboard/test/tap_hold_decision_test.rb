# Tests that an LT/MT key stays undecided until it is released (tap),
# another key is pressed and released inside it (hold), or the tap
# threshold passes (hold). They drive handle_event and
# update_tap_hold_keys through send, so they are skipped on FemtoRuby.
# See keyboard_test.rb for why the keycodes are read through KC.
KC = USB::HID::Keycode if Object.const_defined?(:USB)

class KeyboardTapHoldDecisionTest < Picotest::Test
  def setup
    # handle_event and update_tap_hold_keys are reached with send.
    skip "FemtoRuby's send cannot reach Ruby-defined methods" if femtoruby?
    @kbd = Keyboard.new([0, 1], [2, 3, 4])
    @kbd.layer(:default) do
      row MT(KC::KC_LCTL, KC::KC_A), LT(1, KC::KC_N), LT(1, KC::KC_B)
      row KC::KC_C, KC::KC_D, KC::KC_NO
    end
    @kbd.layer(:sym) do
      row KC::KC_NO, KC::KC_NO, KC::KC_NO
      row KC::KC_LEFT, KC::KC_RIGHT, KC::KC_NO
    end
    # Long enough that only an explicit expire_threshold decides hold
    @kbd.tap_threshold_ms = 10_000
    @events = []
    events = @events
    @kbd.instance_variable_set(:@callback, Proc.new { |e| events << [e[:keycode], e[:modifier]] })
  end

  def press(row, col)
    @kbd.send(:handle_event, {row: row, col: col, pressed: true})
  end

  def release(row, col)
    @kbd.send(:handle_event, {row: row, col: col, pressed: false})
  end

  def expire_threshold
    @kbd.tap_threshold_ms = 0
    @kbd.send(:update_tap_hold_keys)
  end

  def test_rolled_taps_keep_the_typed_order
    press(0, 2)    # B (LT)
    press(1, 0)    # C, held back
    release(0, 2)  # B released first: tap
    release(1, 0)
    assert_equal [[KC::KC_B, 0], [0, 0], [KC::KC_C, 0], [0, 0]], @events
  end

  def test_rolled_lt_keys_both_tap
    press(0, 1)    # N (LT)
    press(0, 2)    # B (LT), held back
    release(0, 1)
    release(0, 2)
    assert_equal [[KC::KC_N, 0], [0, 0], [KC::KC_B, 0], [0, 0]], @events
  end

  def test_key_tapped_inside_lt_uses_the_layer
    press(0, 2)
    press(1, 0)
    assert_equal [], @events  # undecided: nothing sent yet
    release(1, 0)             # pressed and released inside: hold
    assert_equal [[KC::KC_LEFT, 0], [0, 0]], @events
    release(0, 2)
    assert_equal [[KC::KC_LEFT, 0], [0, 0]], @events
    assert_equal [], @kbd.instance_variable_get(:@layer_stack)
  end

  def test_key_tapped_inside_mt_gets_the_modifier
    press(0, 0)    # A (MT LCTL)
    press(1, 0)
    release(1, 0)
    release(0, 0)
    assert_equal [[0, 0x01], [KC::KC_C, 0x01], [0, 0x01], [0, 0]], @events
  end

  def test_threshold_decides_hold_and_flushes_held_back_keys
    press(0, 2)
    press(1, 1)    # D, held back
    expire_threshold
    assert_equal [[KC::KC_RIGHT, 0]], @events
    release(1, 1)
    release(0, 2)
    assert_equal [[KC::KC_RIGHT, 0], [0, 0]], @events
  end

  def test_tap_then_quick_repress_is_not_dropped
    press(0, 0)
    release(0, 0)
    press(0, 0)    # right after the tap: double-tap-hold repeats the tap key
    release(0, 0)
    assert_equal [[KC::KC_A, 0], [0, 0], [KC::KC_A, 0], [0, 0]], @events
  end
end
