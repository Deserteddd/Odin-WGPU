
function setFieldValue(field, value) {
	field.value = value;
	field.textContent = value.toFixed(2);
}

function getFieldValue(field) {
	return field.value ?? parseFloat(field.textContent) ?? 0;
}


function makeDragField(id, startValue = 10, sensitivity = 10) {

	const el = document.getElementById(id);

	if (!el) {
		console.warn("Missing drag field:", id);
		return;
	}

	let dragging = false;

	setFieldValue(el, startValue);

	el.addEventListener("mousedown", () => {

		dragging = true;

		if (document.pointerLockElement !== el) {
			el.requestPointerLock();
		}
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
}

makeDragField("devX", 0, 0.1);
makeDragField("devY", 0, 0.1);
makeDragField("devZ", 0, 0.1);

makeDragField("meanX", 0, 0.1);
makeDragField("meanY", 0, 0.1);
makeDragField("meanZ", 0, 0.1);

makeDragField("fov", 90, 0.2);
makeDragField("zoom", 1, 0.05);
makeDragField("distance", 5, 0.1);