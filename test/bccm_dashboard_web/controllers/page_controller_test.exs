defmodule BccmDashboardWeb.DashboardLiveTest do
  use BccmDashboardWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / renders the operations dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Build pipelines"
    assert html =~ "Service health"
  end
end
