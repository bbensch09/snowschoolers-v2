class LessonsController < ApplicationController
  respond_to :html

  skip_before_action :authenticate_user!, only: [:new, :create]
  before_action :save_lesson_params_and_redirect, only: :create
  before_action :create_lesson_from_session

  def index
    @lessons = Lesson.all
  end

  def new
    @lesson = Lesson.new
    @lesson_time = @lesson.lesson_time
  end

  def create
    create_lesson_and_redirect
  end

  def complete
    @lesson = Lesson.find(params[:id])
    @lesson_time = @lesson.lesson_time
    @state = 'booked'
    flash.now[:notice] = "You're almost there! We just need a few more details."
  end

  def edit
    @lesson = Lesson.find(params[:id])
    @lesson_time = @lesson.lesson_time
    @state = @lesson.instructor ? 'pending instructor' : 'booked'
  end

  def update
    @lesson = Lesson.find(params[:id])
    @original_lesson = @lesson.dup
    @lesson.assign_attributes(lesson_params)
    @lesson.lesson_time = @lesson_time = LessonTime.find_or_create_by(lesson_time_params)
    @lesson.deposit_status = 'confirmed'
    if @lesson.save
      send_lesson_update_notice_to_instructor
      flash[:notice] = 'Thank you, your lesson request was successful. You will receive an email notification when an instructor has been matched to your request. If it has been more than an hour since your request, please email support@snowschoolers.com.'
    else
      determine_update_state
    end
    respond_with @lesson
  end

  def show
    @lesson = Lesson.find(params[:id])
    check_user_permissions
  end

  def destroy
    @lesson = Lesson.find(params[:id])
    @lesson.update(state: 'canceled')
    send_cancellation_email_to_instructor
    flash[:notice] = 'Your lesson has been canceled.'
    redirect_to root_path
  end

  def set_instructor
    @lesson = Lesson.find(params[:id])
    @lesson.instructor_id = current_user.instructor.id
    @lesson.update(state: 'confirmed')
    LessonMailer.send_lesson_confirmation(@lesson).deliver
    redirect_to @lesson
  end

  def remove_instructor
    @lesson = Lesson.find(params[:id])
    send_instructor_cancellation_emails
    @lesson.instructor = nil
    @lesson.update(state: @lesson.available_instructors? ? 'new' : 'pending requester')
    redirect_to @lesson
  end

  def confirm_lesson_time
    @lesson = Lesson.find(params[:id])
    @lesson.update(lesson_params.merge(state: 'waiting for payment'))
    @lesson.state = @lesson.valid? ? 'waiting for payment' : 'confirmed'
    LessonMailer.send_payment_email_to_requester(@lesson).deliver
    respond_with @lesson, action: :show
  end

  private

  def save_lesson_params_and_redirect
    unless current_user
      flash[:alert] = 'You need to sign in or sign up before continuing.'
      session[:lesson] = params[:lesson]
      redirect_to new_user_registration_path and return
    end
  end

  def create_lesson_from_session
    return unless current_user && session[:lesson]
    params[:lesson] = session.delete(:lesson)
    create_lesson_and_redirect
  end

  def create_lesson_and_redirect
    @lesson = Lesson.new(lesson_params)
    @lesson.requester = current_user
    @lesson.lesson_time = @lesson_time = LessonTime.find_or_create_by(lesson_time_params)
    @lesson.save ? (redirect_to complete_lesson_path(@lesson)) : (render :new)
  end

  def send_cancellation_email_to_instructor
    if @lesson.instructor.present?
      LessonMailer.send_cancellation_email_to_instructor(@lesson).deliver
    end
  end

  def send_instructor_cancellation_emails
    LessonMailer.send_lesson_request_to_new_instructors(@lesson, @lesson.instructor).deliver if @lesson.available_instructors?
    LessonMailer.inform_requester_of_instructor_cancellation(@lesson, @lesson.available_instructors?).deliver
    LessonMailer.send_cancellation_confirmation(@lesson).deliver
  end

  def send_lesson_update_notice_to_instructor
    if @lesson.instructor.present?
      changed_attributes = @lesson.get_changed_attributes(@original_lesson)
      return unless changed_attributes.any?

      if @lesson.available_instructors.include?(@lesson.instructor)
        LessonMailer.send_lesson_update_notice_to_instructor(@original_lesson, @lesson, changed_attributes).deliver
      else
        @lesson.instructor = nil
        @lesson.update(state: @lesson.available_instructors? ? 'new' : 'pending requester')
        send_instructor_cancellation_emails
      end
    end
  end

  def check_user_permissions
    unless current_user && (current_user == @lesson.requester || current_user.instructor && current_user.instructor.status == "Active")
      flash[:alert] = "You do not have access to this page."
      redirect_to root_path
    end
  end

  # def format_previous_experiences
  #   previous_experience_ids = params[:lesson][:previous_experience_ids].reject(&:blank?)
  #   previous_experience_ids.map { |id| PreviousExperience.find(id) }
  # end

  def determine_update_state
    @lesson.state = 'new' unless params[:lesson][:terms_accepted] == '1'
    if @lesson.deposit_status == 'confirmed'
      flash.now[:notice] = "Your lesson deposit has been recorded, but your lesson reservation is incomplete. Please fix the fields below and resubmit."
      @lesson.state = 'booked'
    end
      @lesson.save
    @state = params[:lesson][:state]
  end

  def lesson_params
    params.require(:lesson).permit(:activity, :location, :state, :student_count, :gear, :objectives, :duration, :ability_level,
      :start_time, :actual_start_time, :actual_end_time, :terms_accepted, :deposit_status,
      students_attributes: [:id, :name, :age_range, :gender, :relationship_to_requester, :lesson_history, :experience, :_destroy])
  end

  def lesson_time_params
    params[:lesson].require(:lesson_time).permit(:date, :slot)
  end
end
