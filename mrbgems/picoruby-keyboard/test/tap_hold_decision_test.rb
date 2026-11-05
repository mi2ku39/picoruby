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

  def test_repress_after_another_key_is_not_double_tap_hold
    press(0, 2)    # B (LT): tap
    release(0, 2)
    press(1, 1)    # D: ends B's double-tap-hold window
    release(1, 1)
    press(0, 2)    # B again, right away: undecided, not repeating B
    press(1, 0)
    release(1, 0)  # decides hold: LEFT on the layer
    release(0, 2)
    assert_equal [[KC::KC_B, 0], [0, 0], [KC::KC_D, 0], [0, 0],
                  [KC::KC_LEFT, 0], [0, 0]], @events
  end

  def test_rolled_key_after_a_tap_ends_double_tap_hold
    press(0, 2)    # B (LT)
    press(1, 1)    # D, held back while B is undecided
    release(0, 2)  # B tap, then D's press is processed after it
    release(1, 1)
    press(0, 2)    # B again: undecided, not repeating B
    press(1, 0)
    release(1, 0)
    release(0, 2)
    assert_equal [[KC::KC_B, 0], [0, 0], [KC::KC_D, 0], [0, 0],
                  [KC::KC_LEFT, 0], [0, 0]], @events
  end
end

# LT and MT keys held together: the key held back for the other one counts
# its tap threshold from its own press, not from when it is processed.
class KeyboardTapHoldTimingTest < Picotest::Test
  def setup
    # handle_event and update_tap_hold_keys are reached with send.
    skip "FemtoRuby's send cannot reach Ruby-defined methods" if femtoruby?
    at(0)
    @kbd = Keyboard.new([0, 1], [2, 3, 4])
    @kbd.layer(:default) do
      row MT(KC::KC_LSFT, KC::KC_A), LT(1, KC::KC_N), KC::KC_X
      row KC::KC_C, KC::KC_D, KC::KC_NO
    end
    @kbd.layer(:sym) do
      row MT(KC::KC_LSFT, KC::KC_A), KC::KC_NO, KC::KC_1
      row KC::KC_LEFT, KC::KC_RIGHT, KC::KC_NO
    end
    @kbd.tap_threshold_ms = 200
    @events = []
    events = @events
    @kbd.instance_variable_set(:@callback, Proc.new { |e| events << [e[:keycode], e[:modifier]] })
  end

  def at(ms)
    stub(Machine).board_millis { 1000 + ms }
  end

  def tick(ms)
    at(ms)
    @kbd.send(:update_tap_hold_keys)
  end

  def press(row, col)
    @kbd.send(:handle_event, {row: row, col: col, pressed: true})
  end

  def release(row, col)
    @kbd.send(:handle_event, {row: row, col: col, pressed: false})
  end

  def test_mt_held_behind_lt_counts_from_its_press
    press(0, 1)            # LT
    at(10)
    press(0, 0)            # MT, held back
    tick(200)              # LT: hold. MT: 190ms, still undecided
    assert_equal [], @events
    tick(210)              # MT: hold
    assert_equal [[0, 0x02]], @events
    at(300)
    release(0, 0)          # no tap: MT was held for 290ms
    release(0, 1)
    assert_equal [[0, 0x02], [0, 0]], @events
    assert_equal [], @kbd.instance_variable_get(:@layer_stack)
  end

  def test_lt_held_behind_mt_counts_from_its_press
    press(0, 0)            # MT
    at(10)
    press(0, 1)            # LT, held back
    tick(200)              # MT: hold
    tick(210)              # LT: hold
    at(300)
    release(0, 1)          # no tap: LT was held for 290ms
    release(0, 0)
    assert_equal [[0, 0x02], [0, 0]], @events
    assert_equal [], @kbd.instance_variable_get(:@layer_stack)
  end

  def test_events_after_the_threshold_decide_hold_without_a_tick
    press(0, 1)            # LT
    at(10)
    press(0, 0)            # MT, held back
    at(300)                # no update_tap_hold_keys in between
    release(0, 0)          # past both thresholds: both hold, no tap
    release(0, 1)
    assert_equal [[0, 0x02], [0, 0]], @events
    assert_equal [], @kbd.instance_variable_get(:@layer_stack)
  end

  def test_key_pressed_after_the_threshold_uses_the_layer
    press(0, 1)            # LT
    at(250)                # no update_tap_hold_keys in between
    press(0, 2)            # past the threshold: on the hold layer
    assert_equal [[KC::KC_1, 0]], @events  # not held back
    release(0, 2)
    release(0, 1)
    assert_equal [[KC::KC_1, 0], [0, 0]], @events
  end

  def test_rolled_lt_and_mt_within_the_threshold_tap
    press(0, 1)
    at(10)
    press(0, 0)
    tick(20)
    release(0, 1)
    at(30)
    release(0, 0)
    assert_equal [[KC::KC_N, 0], [0, 0], [KC::KC_A, 0], [0, 0]], @events
  end
end
