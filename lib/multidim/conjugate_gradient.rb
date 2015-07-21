# = conjugate_gradient.rb -
# Minimization- Minimization algorithms on pure Ruby
# Copyright (C) 2010 Claudio Bustos
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# This algorith was adopted and ported into Ruby from Apache-commons
# Math library's NonLinearConjugateGradientOptimizer.java file. Therefore this file is under
# Apache License Version 2.
#
# Conjugate Gradient Algorithms for Multidimensional minimization

require "#{File.expand_path(File.dirname(__FILE__))}/point_value_pair.rb"
require "#{File.expand_path(File.dirname(__FILE__))}/../minimization.rb"
require "#{File.expand_path(File.dirname(__FILE__))}/brent_root_finder.rb"

module Minimization

  # Conjugate Gradient minimizer class
  # The beta function may be :fletcher_reeves or :polak_ribiere
  class NonLinearConjugateGradientMinimizer

    attr_reader :x_minimum
    attr_reader :f_minimum
    attr_reader :converging

    attr_accessor :initial_step

    MAX_ITERATIONS_DEFAULT  = 100000
    EPSILON_DEFAULT         = 1e-6

    alias :converging? :converging

    def initialize(f, fd, start_point, beta_formula)
      @epsilon     = EPSILON_DEFAULT
      @safe_min    = 4.503599e15
      @f           = f
      @fd          = fd
      @start_point = start_point

      @max_iterations     = MAX_ITERATIONS_DEFAULT
      @iterations         = 0
      @update_formula     = beta_formula
      @relative_threshold = 100 * @epsilon
      @absolute_threshold = 100 * @safe_min

      @initial_step = 1.0 # initial step default
      @converging   = true

      # do initial steps
      @point = @start_point.clone
      @n      = @point.length
      @r      = gradient(@point)
      0.upto(@n - 1) do |i|
        @r[i] = -@r[i]
      end
      
      # Initial search direction.
      @steepest_descent = precondition(@point, @r)
      @search_direction = @steepest_descent.clone

      @delta = 0
      0.upto(@n - 1) do |i|
          @delta += @r[i] * @search_direction[i]
      end
      @current = nil
    end

    def f(x)
      return @f.call(x)
    end

    def gradient(x)
      return @fd.call(x)
    end

    def find_upper_bound(a, h, search_direction)
      ya   = line_search_func(a, search_direction).to_f
      yb   = ya
      step = h
      # check step value for float max value exceeds
      while step < Float::MAX
        b  = a + step
        yb = line_search_func(b, search_direction).to_f
        if (ya * yb <= 0)
          return b
        end
        step *= [2, ya / yb].max
      end
      # raise error if bracketing failed
      raise "Unable to bracket minimum in line search."
    end

    def precondition(point, r)
      return r.clone # case: identity preconditioner has been used as the default
    end

    def converged(previous, current)
      p          = f(previous)
      c          = f(current)
      difference = (p - c).abs
      size       = [p.abs, c.abs].max
      return ((difference <= size * @relative_threshold) or (difference <= @absolute_threshold))
    end

    # solver to use during line search
    def solve(min, max, start_value, search_direction)
      # check start_value to eliminate unnessasary calculations ...
      func        = proc{|x| line_search_func(x, search_direction)}
      root_finder = Minimization::BrentRootFinder.new(func)
      root        = root_finder.find_root(min, max, func)
      return root
    end

    def line_search_func(x, search_direction)
      # current point in the search direction
      shifted_point = @point.clone
      0.upto(shifted_point.length - 1) do |i|
        shifted_point[i] += x * search_direction[i]
      end

      # gradient of the objective function
      gradient = gradient(shifted_point)

      # dot product with the search direction
      dot_product = 0
      0.upto(gradient.length - 1) do |i|
        dot_product += gradient[i] * search_direction[i]
      end

      return dot_product
    end
    
    # iterate one step of conjugate gradient minimizer
    # == Usage:
    #  f  = proc{ |x| (x[0] - 2)**2 + (x[1] - 5)**2 + (x[2] - 100)**2 }
    #  fd = proc{ |x| [ 2 * (x[0] - 2) , 2 * (x[1] - 5) , 2 * (x[2] - 100) ] }
    #  min = Minimization::FletcherReeves.new(f, fd, [0, 0, 0])
    #  while(min.converging?)
    #    min.iterate
    #  end
    #  min.x_minimum
    #  min.f_minimum
    #
    def iterate
      @iterations  += 1
      @previous     = @current
      @current      = Minimization::PointValuePair.new(@point, f(@point))
      # set converging parameter
      @converging   = !(@previous != nil and converged(@previous.point, @current.point))
      # set results
      @x_minimum    = @current.point
      @f_minimum    = @current.value

      # set search_direction to be used in solve and find_upper_bound methods
      ub   = find_upper_bound(0, @initial_step, @search_direction)
      step = solve(0, ub, 1e-15, @search_direction)

      # Validate new point
      0.upto(@point.length - 1) do |i|
        @point[i] += step * @search_direction[i]
      end

      @r = gradient(@point)
      0.upto(@n - 1) do |i|
        @r[i] = -@r[i]
      end

      # Compute beta
      delta_old            = @delta
      new_steepest_descent = precondition(@point, @r)
      @delta                = 0
      0.upto(@n - 1) do |i|
        @delta += @r[i] * new_steepest_descent[i]
      end

      if (@update_formula == :fletcher_reeves)
        beta = @delta.to_f / delta_old
      elsif(@update_formula == :polak_ribiere)
        deltaMid = 0
        0.upto(@r.length - 1) do |i|
          deltaMid += @r[i] * @steepest_descent[i]
        end
        beta = (@delta - deltaMid).to_f / delta_old
      else
        raise "Unknown beta formula type"
      end
      @steepest_descent = new_steepest_descent

      # Compute conjugate search direction
      if ((@iterations % @n == 0) or (beta < 0))
        # Break conjugation: reset search direction
        @search_direction = @steepest_descent.clone
      else
        # Compute new conjugate search direction
        0.upto(@n - 1) do |i|
          @search_direction[i] = @steepest_descent[i] + beta * @search_direction[i]
        end
      end
    end
  end
  
  
  # = Conjugate Gradient Fletcher Reeves minimizer.
  # A multidimensional minimization methods.
  # == Usage.
  #  require 'minimization'
  #  f  = proc{ |x| (x[0] - 2)**2 + (x[1] - 5)**2 + (x[2] - 100)**2 }
  #  fd = proc{ |x| [ 2 * (x[0] - 2) , 2 * (x[1] - 5) , 2 * (x[2] - 100) ] }
  #  min = Minimization::FletcherReeves.minimize(f, fd, [0, 0, 0])
  #  min.x_minimum
  #  min.f_minimum
  #
  class FletcherReeves < NonLinearConjugateGradientMinimizer
    def initialize(f, fd, start_point)
      super(f, fd, start_point, :fletcher_reeves)
    end

    # Convenience method to minimize using Fletcher Reeves method
    # == Parameters:
    # * <tt>f</tt>: Function to minimize
    # * <tt>fd</tt>: First derivative of f
    # * <tt>start_point</tt>: Starting point
    # == Usage:
    #  f  = proc{ |x| (x[0] - 2)**2 + (x[1] - 5)**2 + (x[2] - 100)**2 }
    #  fd = proc{ |x| [ 2 * (x[0] - 2) , 2 * (x[1] - 5) , 2 * (x[2] - 100) ] }
    #  min = Minimization::FletcherReeves.minimize(f, fd, [0, 0, 0])
    #
    def self.minimize(f, fd, start_point)
      min = Minimization::FletcherReeves.new(f, fd, start_point)
      while(min.converging?)
        min.iterate
      end
      return min
    end
  end

  # = Conjugate Gradient Polak Ribbiere minimizer.
  # A multidimensional minimization methods.
  # == Usage.
  #  require 'minimization'
  #  f  = proc{ |x| (x[0] - 2)**2 + (x[1] - 5)**2 + (x[2] - 100)**2 }
  #  fd = proc{ |x| [ 2 * (x[0] - 2) , 2 * (x[1] - 5) , 2 * (x[2] - 100) ] }
  #  min = Minimization::PolakRibiere.minimize(f, fd, [0, 0, 0])
  #  min.x_minimum
  #  min.f_minimum
  #
  class PolakRibiere < NonLinearConjugateGradientMinimizer
    def initialize(f, fd, start_point)
      super(f, fd, start_point, :polak_ribiere)
    end

    # Convenience method to minimize using Polak Ribiere method
    # == Parameters:
    # * <tt>f</tt>: Function to minimize
    # * <tt>fd</tt>: First derivative of f
    # * <tt>start_point</tt>: Starting point
    # == Usage:
    #  f  = proc{ |x| (x[0] - 2)**2 + (x[1] - 5)**2 + (x[2] - 100)**2 }
    #  fd = proc{ |x| [ 2 * (x[0] - 2) , 2 * (x[1] - 5) , 2 * (x[2] - 100) ] }
    #  min = Minimization::PolakRibiere.minimize(f, fd, [0, 0, 0])
    #
    def self.minimize(f, fd, start_point)
      min = Minimization::PolakRibiere.new(f, fd, start_point)
      while(min.converging?)
        min.iterate
      end
      return min
    end
  end

end
