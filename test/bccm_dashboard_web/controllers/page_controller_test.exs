defmodule BccmDashboardWeb.DashboardLiveTest do
  use BccmDashboardWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / renders the operations dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "BCCM Operations"
    assert has_element?(view, "#refresh-btn")
  end
end
