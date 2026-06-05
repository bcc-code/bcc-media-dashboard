defmodule BccmDashboardWeb.PageController do
  use BccmDashboardWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
