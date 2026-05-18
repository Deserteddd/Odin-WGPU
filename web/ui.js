
function setFieldValue(field, value) {
	field.dataset.value = value;
	field.textContent = Number(value).toFixed(2);

	const o = window.memInterface?.exports;
	if (!o) return;

	switch (field.id) {
		case "devX":
		case "devY":
		case "devZ": {
			const devX = getFieldValue(document.getElementById("devX"));
			const devY = getFieldValue(document.getElementById("devY"));
			const devZ = getFieldValue(document.getElementById("devZ"));

			o.set_dev(devX, devY, devZ);
			break;
		}

		case "meanX":
		case "meanY":
		case "meanZ": {
			const meanX = getFieldValue(document.getElementById("meanX"));
			const meanY = getFieldValue(document.getElementById("meanY"));
			const meanZ = getFieldValue(document.getElementById("meanZ"));

			o.set_mean(meanX, meanY, meanZ);
			break;
		}

		case "zoom":
			o.set_zoom(value);
			break;
	}
}

function getFieldValue(field) {
	return parseFloat(field.dataset.value ?? field.textContent) || 0;
}

function makeDragField(id, startValue = 1, sensitivity = 10) {
	const el = document.getElementById(id);
	if (!el) {
		console.warn("Missing drag field:", id);
		return;
	}

	let dragging = false;
	let editing = false;

	setFieldValue(el, startValue);

	/* dragging */
	el.addEventListener("mousedown", (e) => {

		if (editing) return;
		if (e.button !== 0) return;

		const startX = e.clientX;
		const startY = e.clientY;

		function startDrag(ev) {

			const dx = Math.abs(ev.clientX - startX);
			const dy = Math.abs(ev.clientY - startY);

			/* only start dragging after slight movement */

			if (dx < 3 && dy < 3) return;

			document.removeEventListener("mousemove", startDrag);

			dragging = true;

			if (document.pointerLockElement !== el) {

				el.requestPointerLock();
			}
		}

		document.addEventListener("mousemove", startDrag);

		document.addEventListener("mouseup", () => {

			document.removeEventListener("mousemove", startDrag);

		}, { once: true });
	});

	document.addEventListener("mousemove", (e) => {

		if (!dragging) return;
		if (document.pointerLockElement !== el) return;

		let value = getFieldValue(el);

		value += e.movementX * sensitivity;

		setFieldValue(el, value);
	});

	document.addEventListener("mouseup", () => {

		dragging = false;

		document.exitPointerLock();
	});

	document.addEventListener("pointerlockchange", () => {

		if (document.pointerLockElement !== el) {

			dragging = false;
		}
	});

	/* text input */

	el.addEventListener("dblclick", () => {

		if (editing) return;

		editing = true;

		const currentValue = getFieldValue(el);

		const input = document.createElement("input");

		input.type = "number";
		input.value = currentValue;

		input.style.width = "100%";
		input.style.height = "100%";

		input.style.background = "rgb(60, 60, 60)";
		input.style.border = "none";
		input.style.outline = "none";

		input.style.color = "white";
		input.style.font = "inherit";
		input.style.textAlign = "center";

		el.textContent = "";
		el.appendChild(input);

		input.focus();
		input.select();

		function finish() {

			const newValue = parseFloat(input.value);

			if (!isNaN(newValue)) {
				setFieldValue(el, newValue);
			} else {
				setFieldValue(el, currentValue);
			}

			editing = false;
		}

		input.addEventListener("keydown", (e) => {

			if (e.key === "Enter") {
				finish();
			}

			if (e.key === "Escape") {
				setFieldValue(el, currentValue);
				editing = false;
			}
		});

		input.addEventListener("blur", finish);
	});
}

let simFullscreen = false;

function setSimFullscreen(enabled) {

	simFullscreen = enabled;

	document.body.classList.toggle("sim-fullscreen", enabled);

	/* optional real browser fullscreen */

	if (enabled) {

		document.documentElement.requestFullscreen?.();

	} else {

		document.exitFullscreen?.();
	}
}

document.addEventListener("keydown", (e) => {

	/* toggle with F */

	if (e.key === "f" || e.key === "F") {

		setSimFullscreen(!simFullscreen);
	}

	/* ESC exits */

	if (e.key === "Escape") {

		setSimFullscreen(false);
	}
});

makeDragField("devX", 20, 0.1);
makeDragField("devY", 50, 0.1);
makeDragField("devZ", 20, 0.1);

makeDragField("meanX", 20, 0.1);
makeDragField("meanY", 50, 0.1);
makeDragField("meanZ", 20, 0.1);

makeDragField("fov", 90, 0.2);
makeDragField("zoom", 220, 0.05);
makeDragField("distance", 1, 0.1);