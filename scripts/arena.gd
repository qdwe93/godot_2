class_name Arena
extends RefCounted

## 플레이 영역 크기의 **단일 출처**.
##
## 왜 필요한가
## -----------
## `project.godot`의 stretch 설정이 `mode=canvas_items` + `aspect=expand`다.
## 즉 화면비가 다른 기기에서는 **뷰포트 자체가 넓어진다.** 기준 해상도가
## 1280x720이어도 갤럭시 S21(2400x1080, 20:9)에서는 1600x720이 된다.
##
## 그런데 코드 여러 곳이 `ProjectSettings`의 1280x720을 직접 읽고 있었다. 그래서
## 실측 스크린샷에서 이런 일이 벌어졌다.
##
##   - 배경 ColorRect가 1280까지만 덮어서 오른쪽 320px가 회색으로 남았다
##   - 플레이어는 1280 안에 갇히는데 적은 1600까지 돌아다녔다
##   - HUD의 시계·처치 수가 화면 오른쪽 끝이 아니라 1280 자리에 붙었다
##
## 기기마다 따로 빌드할 문제가 아니다. **크기를 한 곳에서만 읽으면 된다.**
##
## 헤드리스에서의 주의
## -------------------
## 헤드리스 실행은 뷰포트 높이를 틀리게 보고한다 (1280x720인데 1280x1280으로 나온다,
## STATUS 미해결 이슈 2번). 그래서 테스트는 **이 함수가 돌려주는 값을 기준으로**
## 검증한다. 값 자체가 아니라 "플레이어가 이 사각형 안에 갇히는가"라는 관계를 보면
## 헤드리스든 창 모드든 똑같이 성립한다.


## 실제 플레이 영역 크기. 노드는 뷰포트를 찾기 위해서만 쓴다.
static func get_size(node: Node) -> Vector2:
	if node != null and node.is_inside_tree():
		var viewport: Viewport = node.get_viewport()
		if viewport != null:
			var size: Vector2 = viewport.get_visible_rect().size
			if size.x > 0.0 and size.y > 0.0:
				return size
	return get_design_size()


## 기준 해상도. 뷰포트를 못 구할 때의 대비책이며, 트리 밖에서도 쓸 수 있다.
static func get_design_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)


## 뷰포트 좌표계에서의 한가운데. **월드 좌표가 아니다.**
static func get_center(node: Node) -> Vector2:
	return get_size(node) * 0.5


## 화면 한가운데가 가리키는 **월드 좌표**.
##
## M16에서 카메라가 들어오면서 "화면 중앙"과 "뷰포트 크기의 절반"이 더는 같지
## 않게 됐다. 카메라가 (5000, 3000) 을 비추고 있으면 화면 중앙의 월드 좌표도
## 거기다. 적은 **지금 보이는 화면의 바깥**에서 나와야 하므로 스포너는 반드시
## 이 값을 기준으로 잡는다. get_center() 를 쓰면 주인공이 어디로 가든 적이 계속
## 월드 원점 근처에서만 태어난다.
##
## 캔버스 변환의 역행렬을 쓰므로 **카메라가 없어도** 예전과 같은 값이 나온다.
static func get_view_center(node: Node) -> Vector2:
	if node != null and node.is_inside_tree():
		var viewport: Viewport = node.get_viewport()
		if viewport != null:
			var size: Vector2 = viewport.get_visible_rect().size
			if size.x > 0.0 and size.y > 0.0:
				return viewport.get_canvas_transform().affine_inverse() * (size * 0.5)
	return get_design_size() * 0.5


## 적이 생성되는 원의 반지름. 화면 대각선의 절반보다 커야 화면 밖에서 들어온다.
static func get_spawn_radius(node: Node, margin: float) -> float:
	return get_size(node).length() * 0.5 + margin
