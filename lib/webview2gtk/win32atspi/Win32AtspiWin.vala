/* Windows backends for Win32Atspi.generate_keyboard_event */

namespace Win32AtspiWin {

public void synthesize (long keyval, string? keystring, Win32Atspi.KeySynthType synth) {
	if (synth == Win32Atspi.KeySynthType.STRING) {
		if (keystring != null && keystring != "") {
			wv2_a11y_type_text (keystring);
		}
		return;
	}
	/* X11 BackSpace keysym 0xff08 with PRESSRELEASE (AT-SPI keyboard synth). */
	uint16 vk = 0;
	if (keyval == 0xff08 || keyval == 0x08) {
		vk = 0x08; /* VK_BACK */
	} else if (keyval > 0 && keyval < 0x100) {
		vk = (uint16) keyval;
	}
	if (vk != 0 && (synth == Win32Atspi.KeySynthType.PRESSRELEASE
	    || synth == Win32Atspi.KeySynthType.PRESS)) {
		wv2_a11y_key_vk (vk);
	}
}

}
