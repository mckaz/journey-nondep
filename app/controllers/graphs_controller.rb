class GraphsController < ApplicationController
  include ActionView::Helpers::TextHelper
  
  load_resource :questionnaire
  before_filter :set_geom
  respond_to :png
  
  def line
    authorize! :view_answers, @questionnaire

    @questions = Question.where(id: params[:question_ids]).all
    @counts = aggregate_questions(RDL.type_cast(params[:question_ids], "Array<Integer>"))
    @min = @questions.collect { |q| q.min }.min
    @max = @questions.collect { |q| q.max }.max
    
    @graph = Gruff::Line.new(@geom)
  
    i = 0
    ## MKCHANGE: a few below.
    @labels = RDL.type_cast({}, "Hash<Integer, String>", force: true)
    @series = RDL.type_cast({}, "Hash<Question, Array<Integer>>", force: true)
    @min.upto(@max) do |answer|
      @labels[i] = answer.to_s
      @questions.each do |question|
        @series[question] ||= RDL.type_cast([], "Array<Integer>", force: true)
        @series[question] << (@counts[question.id][answer.to_s] || 0)
      end
      i += 1
    end

    @graph.labels = @labels
    @series.each do |question, values|
      @graph.data(question.caption, values)
    end

    @graph.title = "Answer frequency"
    set_journey_theme(@graph)
    
    render text: @graph.to_blob
  end
  
  def pie
    authorize! :view_answers, @questionnaire
    
    @answercounts = aggregate_questions(RDL.type_cast(params[:question_id], "Integer")).values.first
    @question = Question.find(RDL.type_cast(params[:question_id], "Integer"))
    
    @graph = Gruff::Pie.new(@geom)
  
    @answercounts.each do |answer, count|
      @graph.data(answer, [count])
    end

    @graph.title = truncate(@question.caption || "Untitled question")
    set_journey_theme(@graph)
    
    render text: @graph.to_blob
  end
  
  private
  def set_geom
    @geom = params[:geom] || "640x480"
  end
  
  def aggregate_questions(question_ids)
    db = RailsSequel.connect
    
    skip_no_answer = params[:skip_no_answer]
          
    ds = db[:answers]
    ds = ds.inner_join(:questions, :id => :answers__question_id)
    ds = ds.inner_join(:pages, :id => :questions__page_id)
    ds = ds.left_join(:question_options, :question_id => :answers__question_id, :option => :answers__value)
    ds = ds.where(:questions__id => question_ids)
    ds = ds.where(:pages__questionnaire_id => @questionnaire.id)
    ds = ds.select(:questions__id, :answers__value, :question_options__output_value)
    
    counts = RDL.type_cast({}, "Hash<Integer, Hash<String, Integer>>", force: true) ## MKCHANGE
    ds.each do |db_row|
      question_id = RDL.type_cast(db_row[:id], "Integer")
      value = RDL.type_cast((db_row[:output_value] || db_row[:value]), "String")
      if RDL.type_cast(value, "Object").blank?
        if skip_no_answer
          next
        else
          value = "No answer"
        end
      end

      counts[question_id] ||= RDL.type_cast({}, "Hash<String, Integer>", force: true) ## MKCHANGE
      counts[question_id][value] ||= 0
      counts[question_id][value] += 1
    end
    
    unless skip_no_answer
      Question.where(id: question_ids).find_each do |question|
        no_answer = @questionnaire.responses.valid.no_answer_for(RDL.type_cast(question, "Question")).count()
        if no_answer > 0
          counts[RDL.type_cast(question, "Question").id]["No answer"] = no_answer
        end
      end
    end
    
    return counts
  end
  
  private
  def set_journey_theme(graph)
    graph.theme = {
      :colors => %w{#bad032 #5ba5ff #ff7474 #00d686 #8d0081 #ff9500 #512f00},
      :marker_color => 'black',
      :background_colors => ['white', 'white']
      }
  end
end
