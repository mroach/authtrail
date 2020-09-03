require_relative "test_helper"

class AuthTrailTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper # for Rails < 6

  def setup
    User.delete_all
    LoginActivity.delete_all
  end

  def test_success
    user = User.create!(email: "test@example.org", password: "secret")
    post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
    assert_response :found

    assert_equal 1, LoginActivity.count
    login_activity = LoginActivity.last
    assert_equal "user", login_activity.scope
    assert_equal "database_authenticatable", login_activity.strategy
    assert_equal "test@example.org", login_activity.identity
    assert login_activity.success
    assert_nil login_activity.failure_reason
    assert_equal user, login_activity.user
    assert_equal "devise/sessions#create", login_activity.context
  end

  def test_failure
    post user_session_url, params: {user: {email: "test@example.org", password: "bad"}}
    assert_response :unauthorized

    assert_equal 1, LoginActivity.count
    login_activity = LoginActivity.last
    assert_equal "user", login_activity.scope
    assert_equal "database_authenticatable", login_activity.strategy
    assert_equal "test@example.org", login_activity.identity
    refute login_activity.success
    assert_equal "not_found_in_database", login_activity.failure_reason
    assert_nil login_activity.user
    assert_equal "devise/sessions#create", login_activity.context
  end

  def test_exclude_method
    with_options(exclude_method: ->(info) { info[:identity] == "exclude@example.org" }) do
      post user_session_url, params: {user: {email: "exclude@example.org", password: "secret"}}
      assert_empty LoginActivity.all

      post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
      assert_equal 1, LoginActivity.count
    end
  end

  # error reported to safely but doesn't bubble up and doesn't exclude
  def test_exclude_method_error
    with_options(exclude_method: ->(info) { raise "Bad" }) do
      assert_output(nil, "[authtrail] RuntimeError: Bad\n") do
        post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
      end
      assert_equal 1, LoginActivity.count
    end
  end

  def test_geocode_true
    assert_enqueued_with(job: AuthTrail::GeocodeJob, queue: "default") do
      post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
    end
  end

  def test_geocode_false
    with_options(geocode: false) do
      post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
      assert_equal 0, enqueued_jobs.size
    end
  end

  def test_job_queue
    with_options(job_queue: :low_priority) do
      assert_enqueued_with(job: AuthTrail::GeocodeJob, queue: "low_priority") do
        post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
      end
    end
  end

  def test_request_info_method
    with_options(request_info_method: ->(info, request) { info[:request_id] = request.uuid }) do
      post user_session_url, params: {user: {email: "exclude@example.org", password: "secret"}}
      assert LoginActivity.last.request_id
    end
  end

  def test_request_info_method_exclude
    options = {
      request_info_method: ->(info, request) { info[:exclude] = true },
      exclude_method: ->(info) { info[:exclude] }
    }
    with_options(**options) do
      post user_session_url, params: {user: {email: "test@example.org", password: "secret"}}
      assert_empty LoginActivity.all
    end
  end
end
